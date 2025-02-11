import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'package:shadow_connect/screens/conversationsScreen/group_chat_screen.dart';
import 'chat_screen.dart';

class ConnectionsScreen extends StatefulWidget {
  final String messageToForward;
  final bool isAddingParticipants;
  final String? conversationId; // Add conversationId as a parameter

  const ConnectionsScreen({
    super.key,
    this.messageToForward = '',
    this.isAddingParticipants = false,
    this.conversationId, // Optional parameter
  });

  @override
  _ConnectionsScreenState createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  Set<String> selectedUserIds = {};
  Set<String> adminUserIds = {};

  // Optimized method to fetch connections
  Future<List<Map<String, dynamic>>> getConnections() async {
    String currentUserUid = FirebaseAuth.instance.currentUser!.uid;

    var snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserUid)
        .collection('connections')
        .get();

    return snapshot.docs.map((doc) {
      return {
        'username': doc['username'],
        'uid': doc['uid'],
      };
    }).toList();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Method to create the group chat
  void _createGroupChat() async {
    if (selectedUserIds.isEmpty || selectedUserIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Please select at least two users to create a group')),
      );
      return;
    }

    String currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    selectedUserIds.add(currentUserUid);
    adminUserIds.add(currentUserUid);

    // Show an AlertDialog to input the group name
    String groupName = await _showGroupNameDialog();

    if (groupName.isEmpty) {
      // If no group name is provided, set a default name
      groupName = 'Group Chat';
    }

    String groupId = selectedUserIds
        .toList()
        .join('_'); // Combine selected UIDs to form a unique group ID

    // Create group chat data
    DocumentReference groupChatRef =
        FirebaseFirestore.instance.collection('conversations').doc(groupId);

    // Create group chat if it doesn't exist
    await groupChatRef.set({
      'participants': List<String>.from(selectedUserIds),
      'admins': List<String>.from(adminUserIds),
      'groupName': groupName, // Set the entered group name
      'lastMessage': widget.messageToForward,
      'lastMessageTimestamp': DateTime.now().millisecondsSinceEpoch,
      'unreadMessages': {currentUserUid: 0},
      'totalMessages': 0,
    });

    // Navigate to the group chat screen with updated parameters
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChatScreen(
          groupId: groupId,
          participantIds: List<String>.from(selectedUserIds),
          adminIds: List<String>.from(adminUserIds),
          groupName: groupName, // Pass the entered group name
          currentUserUid: currentUserUid,
        ),
      ),
    );
  }

// Function to show AlertDialog to input group name
  Future<String> _showGroupNameDialog() async {
    String groupName = '';

    await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        TextEditingController _controller = TextEditingController();

        return AlertDialog(
          title: const Text('Enter Group Name'),
          content: TextField(
            controller: _controller,
            decoration: const InputDecoration(hintText: 'Group Name'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                groupName = _controller.text.trim();
                Navigator.pop(context); // Close the dialog
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    return groupName;
  }

  Future _forwardMessageToUsers(
      List<String> selectedUserIds, String messageToForward) async {
    if (messageToForward.isNotEmpty && selectedUserIds.isNotEmpty) {
      String currentUserUid = FirebaseAuth.instance.currentUser!.uid;
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      for (String userId in selectedUserIds) {
        // Generate or fetch the conversation ID between the current user and recipient
        String conversationId =
            await _getExistingConversationId(currentUserUid, userId);

        // Reference to the conversation document
        DocumentReference conversationRef =
            _firestore.collection('conversations').doc(conversationId);
        CollectionReference messagesRef =
            conversationRef.collection('messages');

        // Prepare the message data
        Map<String, dynamic> forwardedMessageData = {
          'message': messageToForward,
          'senderId': currentUserUid,
          'recipientId': userId,
          'time': timestamp,
          'isEncrypted': false, // Adjust based on your message encryption logic
          'isDeleted': false,
          'isRead': false,
          'isForwarded': true, // Mark the message as forwarded
        };

        // Send the forwarded message
        await messagesRef.add(forwardedMessageData);

        // Update the conversation document with the last message info
        await conversationRef.set({
          'participants': [currentUserUid, userId],
          'lastMessage': messageToForward,
          'lastMessageTimestamp': timestamp,
          'unreadMessages': {
            userId: FieldValue.increment(1),
            currentUserUid: 0,
          },
          'totalMessages': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Message forwarded to selected users!')));
    }
  }

// Helper method to check if an existing conversation exists and return its conversationId
  Future<String> _getExistingConversationId(
      String currentUserUid, String targetUserId) async {
    // Sort the user IDs to ensure consistency in conversation ID
    List<String> sortedIds = [currentUserUid, targetUserId]..sort();
    String conversationId = sortedIds.join('_');

    // Check if a conversation with the generated ID already exists
    DocumentSnapshot conversationSnapshot = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .get();

    // If the conversation exists, return the existing conversationId
    if (conversationSnapshot.exists) {
      return conversationId;
    } else {
      // If no conversation exists, generate a new one (this case should be rare)
      return conversationId;
    }
  }

  // Helper method to generate a conversation ID between two users

  void _confirmAddParticipants() async {
  // Check if any users are selected
  if (selectedUserIds.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No participants selected!')),
    );
    return;
  }

  // Add selected participants to the group (update Firestore)
  try {
    // First, fetch the current unreadMessages map from Firestore
    DocumentSnapshot groupDoc = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .get();

    Map<String, dynamic> groupData = groupDoc.data() as Map<String, dynamic>;
    Map<String, dynamic> currentUnreadMessages = Map<String, dynamic>.from(groupData['unreadMessages'] ?? {});

    // Add selected participants to the group (update participants array)
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId)
        .update({
      'participants': FieldValue.arrayUnion(selectedUserIds.toList()), // Add participants to the array
    });

    // Update unreadMessages map with the new participants without overwriting existing data
    Map<String, dynamic> unreadMessagesMap = {};
    for (String userId in selectedUserIds) {
      // Only add the user to unreadMessages if they don't already exist in the map
      if (!currentUnreadMessages.containsKey(userId)) {
        unreadMessagesMap[userId] = 0; // Initialize unread message count for each new participant
      }
    }

    if (unreadMessagesMap.isNotEmpty) {
      // Merge the new unreadMessages data with the existing data
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(widget.conversationId)
          .update({
        'unreadMessages': {
          ...currentUnreadMessages, // Keep existing unreadMessages
          ...unreadMessagesMap, // Add new unreadMessages entries
        },
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Participants added successfully!')),
    );

    // Navigate back or pop the screen to return to the group chat
    Navigator.pop(context); // Pop to return to previous screen
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error adding participants: $e')),
    );
  }
}



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      appBar: AppBar(
        title: const Text("Connections", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.blackIndigoDark,
        actions: [
          if (selectedUserIds.isNotEmpty &&
              !widget.isAddingParticipants) // Disable if adding participants
            IconButton(
              icon: const Icon(Icons.group_add),
              onPressed: widget.isAddingParticipants
                  ? null
                  : _createGroupChat, // Disable if adding participants
            ),
          if (widget.messageToForward.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () => _forwardMessageToUsers(
                  List<String>.from(selectedUserIds),
                  widget.messageToForward), // Forward message to selected users
            ),
          if (widget.isAddingParticipants)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed:
                  _confirmAddParticipants, // Call method to confirm addition
            ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: getConnections(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No connections found.'));
          }

          var connections = snapshot.data!;

          return ListView.builder(
            itemCount: connections.length,
            itemBuilder: (context, index) {
              var connection = connections[index];

              return Card(
                elevation: 4.0,
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.0),
                ),
                color: AppColors.blackIndigoLight,
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  title: Text(connection['username'],
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold)),
                  subtitle: Text('Tap to chat',
                      style:
                          TextStyle(color: Colors.grey[400], fontSize: 14.0)),
                  trailing: Checkbox(
                    value: selectedUserIds.contains(connection['uid']),
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          selectedUserIds.add(connection['uid']);
                        } else {
                          selectedUserIds.remove(connection['uid']);
                        }
                      });
                    },
                  ),
                  onTap: () {
                    if (widget.messageToForward.isEmpty) {
                      String currentUserUid =
                          FirebaseAuth.instance.currentUser!.uid;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(
                            uid: currentUserUid,
                            recipientUid: connection['uid'],
                            recipientUsername: connection['username'],
                          ),
                        ),
                      );
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
