import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'chat_screen.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  Future<List<Map<String, dynamic>>> getConnections() async {
    // Get the current user's UID dynamically
    String currentUserUid = FirebaseAuth.instance.currentUser!.uid;

    var snapshot = await FirebaseFirestore.instance
        .collection('users') // Users collection
        .doc(currentUserUid) // Current user document
        .collection('connections') // Connections subcollection
        .get();

    // Map the fetched documents into a list of maps containing usernames and UIDs
    return snapshot.docs
        .map((doc) => {
              'username':
                  doc['username'], // Assuming there's a 'username' field
              'uid': doc['uid'], // Recipient UID
            })
        .toList();
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
                margin: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
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
                  trailing: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                  ),
                  onTap: () {
                    String currentUserUid =
                        FirebaseAuth.instance.currentUser!.uid;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          uid: currentUserUid, // Pass current user's UID
                          recipientUid: connection['uid'], // Pass recipient UID
                          recipientUsername:
                              connection['username'], // Pass recipient username
                        ),
                      ),
                    );
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
