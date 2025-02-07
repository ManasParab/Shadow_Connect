import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'connections_screen.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  /// Fetches conversations involving the current user
  Stream<List<Map<String, dynamic>>> getConversations() {
    String currentUserUid = FirebaseAuth.instance.currentUser!.uid;

    return FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: currentUserUid)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        var data = doc.data();

        // Get recipient UID
        List<String> participants = List<String>.from(data['participants']);
        String recipientUid = participants
            .firstWhere((uid) => uid != currentUserUid, orElse: () => '');

        // Fetch the latest message and unread count
        String latestMessage = data['lastMessage'] ?? 'No messages yet';
        int timestamp = data['lastMessageTimestamp'] ?? 0;
        int unreadCount = data['unreadMessages']?[currentUserUid] ?? 0;

        return {
          'conversationId': doc.id,
          'recipientUid': recipientUid,
          'latestMessage': latestMessage,
          'timestamp': timestamp,
          'unreadCount': unreadCount,
        };
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      appBar: AppBar(
        title: const Text(
          "Conversations",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.blackIndigoDark,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: getConversations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
                child: Text(
              'No conversations found.',
              style: TextStyle(color: Colors.white),
            ));
          }

          var conversations = snapshot.data!;
          conversations
              .sort((a, b) => b['timestamp'].compareTo(a['timestamp']));

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              var conversation = conversations[index];

              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(conversation['recipientUid'])
                    .get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                    return Container(); // Skip if user not found
                  }
                  var userData = userSnapshot.data!;
                  String recipientUsername = userData['username'];

                  return Card(
                    elevation: 4.0,
                    margin:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.0),
                    ),
                    color: AppColors.blackIndigoLight,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      title: Text(
                        recipientUsername,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        conversation['latestMessage'].length > 30
                            ? "${conversation['latestMessage'].substring(0, 30)}..." // Truncate
                            : conversation['latestMessage'],
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14.0,
                        ),
                      ),
                      trailing: conversation['unreadCount'] > 0
                          ? Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${conversation['unreadCount']}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : const SizedBox(), // If no unread messages, show nothing
                      onTap: () {
                        String currentUserUid =
                            FirebaseAuth.instance.currentUser!.uid;

                        // Reset unread count to 0 when opening chat
                        FirebaseFirestore.instance
                            .collection('conversations')
                            .doc(conversation['conversationId'])
                            .update({'unreadMessages.$currentUserUid': 0});

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatScreen(
                              uid: currentUserUid, // Pass current user's UID
                              recipientUid: conversation[
                                  'recipientUid'], // Pass recipient UID
                              recipientUsername:
                                  recipientUsername, // Pass recipient username
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ConnectionsScreen(),
            ),
          );
        },
        backgroundColor: AppColors.Indigo,
        child: const Icon(
          Icons.add,
          color: Colors.white,
        ),
      ),
    );
  }
}
