import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'package:shadow_connect/screens/conversationsScreen/group_chat_screen.dart';
import 'chat_screen.dart';

class ConnectionsScreen extends StatefulWidget {
  final String messageToForward;
  const ConnectionsScreen({super.key, this.messageToForward = ''});

  @override
  _ConnectionsScreenState createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  Set<String> selectedUserIds = {};

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

  // Method to create the group chat
  void _createGroupChat() async {
    if (selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one user to create a group')),
      );
      return;
    }

    String currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    selectedUserIds.add(currentUserUid);

    String groupId = selectedUserIds.toList().join('_'); // Combine selected UIDs to form a unique group ID

    // Create group chat data
    DocumentReference groupChatRef = FirebaseFirestore.instance.collection('conversations').doc(groupId);

    // Create group chat if it doesn't exist
    await groupChatRef.set({
      'participants': List<String>.from(selectedUserIds),
      'groupName': 'Group Chat', // Customize if needed
      'lastMessage': widget.messageToForward,
      'lastMessageTimestamp': DateTime.now().millisecondsSinceEpoch,
      'unreadMessages': {currentUserUid: 0},
      'totalMessages': 0,
    });

    // Add the forwarded message (if any)
    if (widget.messageToForward.isNotEmpty) {
      await groupChatRef.collection('messages').add({
        'message': widget.messageToForward,
        'senderId': currentUserUid,
        'time': DateTime.now().millisecondsSinceEpoch,
        'isEncrypted': false,
        'isDeleted': false,
        'isRead': false,
        'isForwarded': true,
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group chat created!')));

    // Navigate to the group chat screen with updated parameters
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GroupChatScreen(
          groupId: groupId,
          participantIds: List<String>.from(selectedUserIds),
          groupName: 'Group Chat', // Customize if needed
          currentUserUid: currentUserUid,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      appBar: AppBar(
        title: const Text("Connections", style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.blackIndigoDark,
        actions: [
          if (selectedUserIds.isNotEmpty) // Show create group button if users are selected
            IconButton(
              icon: const Icon(Icons.group_add),
              onPressed: _createGroupChat,
            ),
          if (widget.messageToForward.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _createGroupChat, // Forward message to group chat
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
                      style: const TextStyle(color: Colors.white, fontSize: 18.0, fontWeight: FontWeight.bold)),
                  subtitle: Text('Tap to chat', style: TextStyle(color: Colors.grey[400], fontSize: 14.0)),
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
                      String currentUserUid = FirebaseAuth.instance.currentUser!.uid;
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
