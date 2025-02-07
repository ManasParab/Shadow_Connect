import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shadow_connect/constants/colors.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  _ConnectionsScreenState createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchedUsername = '';
  Map<String, dynamic> _foundUser = {};
  bool _isRequestSent = false;
  bool _isRequestReceived = false;
  bool _isConnected = false;
  bool _isRequestPending = false;

  // Search Result Visibility
  bool _isSearchResultVisible = false;

  Future<void> _searchUser() async {
    String username = _searchController.text.trim();
    if (username.isEmpty) return;

    print(
        'Searching for username: $username'); // Debug: Check the username being searched

    // Fetch the user document directly using the username as the document ID
    var userDoc = await _firestore.collection('usernames').doc(username).get();

    if (userDoc.exists) {
      String uid = userDoc['uid'];
      print(
          'User found with UID: $uid'); // Debug: Check if user is found with UID

      var userSnapshot = await _firestore.collection('users').doc(uid).get();

      if (userSnapshot.exists) {
        var currentUserUid = _auth.currentUser!.uid;

        // Check if already connected
        var connectionDoc = await _firestore
            .collection('users')
            .doc(currentUserUid)
            .collection('connections')
            .doc(uid)
            .get();

        // Check if a request is pending
        var requestDoc = await _firestore
            .collection('users')
            .doc(uid)
            .collection('connection-requests')
            .doc(currentUserUid)
            .get();

        setState(() {
          _foundUser = userSnapshot.data()!;
          _searchedUsername = username;
          _isConnected = connectionDoc.exists;
          _isRequestPending =
              requestDoc.exists && requestDoc['status'] == 'pending';
          _isRequestSent = false;
          _isRequestReceived =
              requestDoc.exists && requestDoc['status'] == 'pending';
          _isSearchResultVisible = true; // Show search result
        });

        print('User details: $_foundUser'); // Debug: Print found user details
      }
    } else {
      print(
          'No user found with the username: $username'); // Debug: No user found
      setState(() {
        _foundUser = {};
        _searchedUsername = '';
        _isSearchResultVisible = false; // Hide search result if not found
      });
    }
  }

  // Function to send a connection request
  Future<void> _sendConnectionRequest(String recipientUid) async {
    String senderUid = _auth.currentUser!.uid;

    // Fetch current user's username
    var senderSnapshot =
        await _firestore.collection('users').doc(senderUid).get();
    String senderUsername =
        senderSnapshot['username']; // Fetching the sender's username

    // Create a document in the connection-requests sub-collection
    await _firestore
        .collection('users')
        .doc(recipientUid)
        .collection('connection-requests')
        .doc(senderUid)
        .set({
      'senderUid': senderUid,
      'Username': senderUsername, // Store the sender's username
      'status': 'pending',
      'timestamp': FieldValue.serverTimestamp(),
    });

    setState(() {
      _isRequestSent = true;
    });
  }

  Future<void> _acceptConnectionRequest(
      String senderUid, String senderUsername) async {
    try {
      // Fetch the current user's data (e.g., `manasparab`)
      var currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Get the current user's username
      DocumentSnapshot currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      String currentUserUsername = currentUserDoc['username'];

      // Add to the current user's connections
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('connections')
          .doc(senderUid)
          .set({
        'uid': senderUid,
        'username': senderUsername, // Make sure the sender's username is passed
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Add to the sender's connections
      await FirebaseFirestore.instance
          .collection('users')
          .doc(senderUid)
          .collection('connections')
          .doc(currentUser.uid)
          .set({
        'uid': currentUser.uid,
        'username':
            currentUserUsername, // Ensure current user's username is passed
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Delete the connection request from both users
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('connection-requests')
          .doc(senderUid)
          .delete();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(senderUid)
          .collection('connection-requests')
          .doc(currentUser.uid)
          .delete();
    } catch (e) {
      print('Error accepting connection request: $e');
    }
  }

  // Function to remove a connection with confirmation
  Future<void> _removeConnection(String connectionUid) async {
    // Show a confirmation dialog before removing the connection
    bool? confirmation = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Removal'),
          content: const Text('Are you sure you want to remove this connection?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context)
                    .pop(false); // Close dialog and return false
              },
            ),
            TextButton(
              child: const Text('Remove'),
              onPressed: () {
                Navigator.of(context).pop(true); // Close dialog and return true
              },
            ),
          ],
        );
      },
    );

    // If the user confirmed the removal, proceed with the action
    if (confirmation == true) {
      String currentUserUid = _auth.currentUser!.uid;

      // Remove from sender's connections
      await _firestore
          .collection('users')
          .doc(currentUserUid)
          .collection('connections')
          .doc(connectionUid)
          .delete();

      // Remove from receiver's connections
      await _firestore
          .collection('users')
          .doc(connectionUid)
          .collection('connections')
          .doc(currentUserUid)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection removed successfully!')));

      setState(() {
        // Optionally refresh UI after removal
      });
    } else {
      // If the user did not confirm, do nothing (just close the dialog)
      print('Connection removal canceled');
    }
  }

  // Function to block a user
  Future<void> _blockUser(String connectionUid) async {
    String currentUserUid = _auth.currentUser!.uid;
    await _firestore
        .collection('users')
        .doc(currentUserUid)
        .collection('blocked-users')
        .doc(connectionUid)
        .set({
      'uid': connectionUid,
      'timestamp': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('User blocked successfully!')));
  }

  // Function to mute a user
  Future<void> _muteUser(String connectionUid) async {
    String currentUserUid = _auth.currentUser!.uid;
    await _firestore
        .collection('users')
        .doc(currentUserUid)
        .collection('muted-users')
        .doc(connectionUid)
        .set({
      'uid': connectionUid,
      'timestamp': FieldValue.serverTimestamp(),
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('User muted successfully!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(18.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => _searchUser(),
              decoration: const InputDecoration(
                filled: true,
                fillColor: AppColors.blackIndigoLight,
                border: OutlineInputBorder(
                  borderSide: BorderSide(
                    color: AppColors.whiteGrey,
                  ),
                ),
                hintText: "Search for connections...",
                hintStyle: TextStyle(fontSize: 16, color: AppColors.grey),
              ),
            ),
          ),
          Expanded(
            child: DefaultTabController(
              initialIndex: 0, // Set the default tab to "Search Results"
              length: 3, // 3 tabs: Connections, Requests, Search Results
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: "Search Results"),
                      Tab(text: "Connections"),
                      Tab(text: "Requests"),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Search Results Tab
                        _isSearchResultVisible
                            ? ListView(
                                children: [
                                  ListTile(
                                    title: Text(
                                      _foundUser['username'],
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    subtitle: const Text('User found',
                                        style: TextStyle(color: Colors.white)),
                                    trailing: _isConnected
                                        ? ElevatedButton(
                                            onPressed: () {
                                              // Handle Remove Connection
                                              _removeConnection(
                                                  _foundUser['uid']);
                                            },
                                            child: const Text('Remove'),
                                          )
                                        : ElevatedButton(
                                            onPressed: () {
                                              // Handle Send Request
                                              _sendConnectionRequest(
                                                  _foundUser['uid']);
                                            },
                                            child: const Text('Send Request'),
                                          ),
                                  )
                                ],
                              )
                            : const Center(
                                child: Text('No result found.',
                                    style: TextStyle(color: Colors.white)),
                              ),
                        // Connections Tab
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('users')
                              .doc(_auth.currentUser!.uid)
                              .collection('connections')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            var connections = snapshot.data!.docs;
                            if (connections.isEmpty) {
                              return const Center(
                                  child: Text('No connections',
                                      style: TextStyle(color: Colors.white)));
                            }

                            // Inside the Connections Tab StreamBuilder
                            return ListView.builder(
                              itemCount: connections.length,
                              itemBuilder: (context, index) {
                                var connection = connections[index];
                                var connectionUid = connection['uid'];
                                var connectionUsername = connection['username'];

                                return ListTile(
                                  title: Text(
                                    connectionUsername,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (String value) {
                                      switch (value) {
                                        case 'remove':
                                          _removeConnection(
                                              connectionUid); // Remove connection
                                          break;
                                        case 'block':
                                          _blockUser(
                                              connectionUid); // Block user
                                          break;
                                        case 'mute':
                                          _muteUser(connectionUid); // Mute user
                                          break;
                                        default:
                                          break;
                                      }
                                    },
                                    itemBuilder: (BuildContext context) {
                                      return [
                                        const PopupMenuItem<String>(
                                          value: 'remove',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.remove_circle_outline,
                                                  color: Colors.white),
                                              const SizedBox(width: 8),
                                              const Text('Remove',
                                                  style: TextStyle(
                                                      color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'block',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.block,
                                                  color: Colors.white),
                                              const SizedBox(width: 8),
                                              const Text('Block',
                                                  style: TextStyle(
                                                      color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem<String>(
                                          value: 'mute',
                                          child: Row(
                                            children: [
                                              const Icon(Icons.volume_off,
                                                  color: Colors.white),
                                              const SizedBox(width: 8),
                                              const Text('Mute',
                                                  style: TextStyle(
                                                      color: Colors.white)),
                                            ],
                                          ),
                                        ),
                                      ];
                                    },
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        // Requests Tab
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('users')
                              .doc(_auth.currentUser!.uid)
                              .collection('connection-requests')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }

                            var requests = snapshot.data!.docs;
                            if (requests.isEmpty) {
                              return const Center(
                                  child: Text('No connection requests',
                                      style: TextStyle(color: Colors.white)));
                            }

                            return ListView.builder(
                              itemCount: requests.length,
                              itemBuilder: (context, index) {
                                var request = requests[index];
                                var senderUid = request['senderUid'];
                                var senderUsername = request['Username'];

                                return ListTile(
                                  title: Text(
                                    senderUsername,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton(
                                        onPressed: () {
                                          // Handle Accept Request
                                          _acceptConnectionRequest(
                                              senderUid, senderUsername);
                                        },
                                        child: const Text('Accept'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
