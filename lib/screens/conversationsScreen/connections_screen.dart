import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'chat_screen.dart';

class ConnectionsScreen extends StatefulWidget {
  final String
      messageToForward; // Content to forward, defaulting to an empty string if not provided
  const ConnectionsScreen({super.key, this.messageToForward = ''});

  @override
  _ConnectionsScreenState createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  bool isForwarding = false; // Flag to track if forwarding is in progress
  Set<String> selectedUserIds = {}; // Store selected user IDs

  Future<List<Map<String, dynamic>>> getConnections() async {
    String currentUserUid = FirebaseAuth.instance.currentUser!.uid;

    var snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserUid)
        .collection('connections')
        .get();

    return snapshot.docs
        .map((doc) => {
              'username': doc['username'],
              'uid': doc['uid'],
            })
        .toList();
  }

  void _sendForwardedMessages() {
    if (selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select at least one user to forward')),
      );
      return;
    }

    // Logic to forward the message to selected users
    selectedUserIds.forEach((recipientUid) async {
      // Generate a unique conversation ID using the sender and recipient UIDs
      String senderUid = FirebaseAuth.instance.currentUser!.uid;
      String conversationId = senderUid.compareTo(recipientUid) < 0
          ? '$senderUid' '_' '$recipientUid'
          : '$recipientUid' '_' '$senderUid';

      // Reference to the conversation and messages sub-collection
      DocumentReference conversationRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(conversationId);
      CollectionReference messagesRef = conversationRef.collection('messages');

      // Create the message data

      Map<String, dynamic> messageData = {
        'message': widget.messageToForward,
        'senderId': senderUid,
        'recipientId': recipientUid,
        'time': DateTime.now().millisecondsSinceEpoch,
        'isEncrypted': false,
        'isDeleted': false,
        'isRead': false,
        'isForwarded': true, // Mark the message as forwarded
      };

      // Add the message to the messages sub-collection
      await messagesRef.add(messageData);

      // Update the conversation with the last message details
      await conversationRef.set({
        'participants': [senderUid, recipientUid],
        'lastMessage': widget.messageToForward,
        'lastMessageTimestamp': DateTime.now().millisecondsSinceEpoch,
        'unreadMessages': {
          recipientUid: FieldValue.increment(1),
          senderUid: 0,
        },
        'totalMessages': FieldValue.increment(1), // Increment totalMessages
      }, SetOptions(merge: true));
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Messages forwarded!')));

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      appBar: AppBar(
        title: const Text(
          "Connections",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.blackIndigoDark,
        actions: [
          if (widget.messageToForward
              .isNotEmpty) // Show the send button only when forwarding
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _sendForwardedMessages,
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
                  title: Text(
                    connection['username'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    'Tap to chat',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 14.0,
                    ),
                  ),
                  trailing: widget.messageToForward.isNotEmpty
                      ? Checkbox(
                          value: selectedUserIds.contains(connection['uid']),
                          onChanged: (bool? value) {
                            setState(() {
                              if (value == true) {
                                if (selectedUserIds.length < 15) {
                                  selectedUserIds.add(connection['uid']);
                                }
                              } else {
                                selectedUserIds.remove(connection['uid']);
                              }
                            });
                          },
                        )
                      : const Icon(
                          Icons.chat_bubble_outline,
                          color: Colors.white,
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
