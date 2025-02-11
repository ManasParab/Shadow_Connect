import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'connections_screen.dart';
import 'package:shadow_connect/main.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final List<String> participantIds;
  final List<String> adminIds;
  final String groupName;
  final String currentUserUid;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.participantIds,
    required this.adminIds,
    required this.groupName,
    required this.currentUserUid,
  });

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  bool _isSendingEncrypted = false;
  bool _isBulkActionMode = false;
  final _key = encrypt.Key.fromUtf8('32charlengthfor256bitkey12345678');
  final _iv = encrypt.IV.fromLength(16);
  // Fetch all user details before showing the dialog
  List<Map<String, dynamic>> participantDetails = [];
  List<String> admins = [];

  Set<String> _selectedMessages = {};

  @override
  void initState() {
    super.initState();
    _fetchGroupSettingsData();
  }

  String get conversationId {
    return widget.groupId;
  }

  String formatTimestamp(DateTime timestamp) {
    String date = DateFormat('dd/MM/yy').format(timestamp);
    String time = DateFormat('hh:mm a').format(timestamp);
    return '$date $time';
  }

  Future sendMessage({bool isEncrypted = true}) async {
    if (_controller.text.isNotEmpty) {
      String message = _controller.text.trim();
      if (message.isNotEmpty) {
        message = message[0].toUpperCase() + message.substring(1);
      }
      _controller.clear();
      await _sendMessage(message, isEncrypted);
      _isSendingEncrypted = false;
    }
  }

  Future _sendMessage(String message, bool isEncrypted) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    String messageToSend = message;

    if (isEncrypted) {
      messageToSend = encryptMessage(message);
    }

    DocumentReference conversationRef =
        _firestore.collection('conversations').doc(widget.groupId);
    CollectionReference messagesRef = conversationRef.collection('messages');

    Map<String, dynamic> messageData = {
      'message': messageToSend,
      'senderId': widget.currentUserUid,
      'time': timestamp,
      'isEncrypted': isEncrypted,
      'isDeleted': false,
      'isRead': false,
      'isForwarded': false,
    };

    // Add the message to the messages sub-collection
    await messagesRef.add(messageData);

    // Update the conversation's last message and total message count
    await conversationRef.set({
      'participants': widget.participantIds,
      'lastMessage': messageToSend,
      'lastMessageTimestamp': timestamp,
      'totalMessages': FieldValue.increment(1),
    }, SetOptions(merge: true));

    // Update the unreadMessages count for each participant (except the sender)
    for (String participantId in widget.participantIds) {
      if (participantId != widget.currentUserUid) {
        // Increment the unreadMessages count for this participant
        await conversationRef.update({
          'unreadMessages.$participantId': FieldValue.increment(1),
        });
      }
    }

    Future.delayed(const Duration(milliseconds: 300), () {
      _scrollToBottom();
    });
  }

  String encryptMessage(String message) {
    final key = encrypt.Key.fromUtf8('32charlengthfor256bitkey12345678');
    final iv = encrypt.IV.fromLength(16);
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final encrypted = encrypter.encrypt(message, iv: iv);
    final encodedIV = base64.encode(iv.bytes);
    final encodedMessage = encrypted.base64;
    return '$encodedIV:$encodedMessage';
  }

  Future _markMessageAsRead(String messageId) async {
    await _firestore
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({'isRead': true});

    await _firestore.collection('conversations').doc(conversationId).update({
      'unreadMessages.${widget.currentUserUid}': FieldValue.increment(-1),
    });
  }

  Future _authenticateUser() async {
    try {
      final bool canAuthenticate =
          await _localAuthentication.canCheckBiometrics ||
              await _localAuthentication.isDeviceSupported();

      if (!canAuthenticate) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No authentication methods available')));

        return false;
      }

      return await _localAuthentication.authenticate(
        localizedReason: 'Authenticate to view encrypted message',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException catch (e) {
      print('Auth Error: ${e.code} - ${e.message}');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication error: ${e.code}')));

      return false;
    }
  }

  String decryptMessage(String encryptedMessage) {
    try {
      final key = encrypt.Key.fromUtf8('32charlengthfor256bitkey12345678');
      final parts = encryptedMessage.split(':');
      if (parts.length != 2) return '';
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encryptedText = parts[1];
      final encrypter =
          encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
      return encrypter.decrypt64(encryptedText, iv: iv);
    } catch (e) {
      print('Decryption failed: $e');
      return '';
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // Function to fetch group settings data before showing dialog
  Future<void> _fetchGroupSettingsData() async {
    try {
      var groupDoc = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();

      if (!groupDoc.exists) return;

      var groupData = groupDoc.data() as Map<String, dynamic>? ?? {};

      List<String> participants =
          List<String>.from(groupData['participants'] ?? []);
      admins = List<String>.from(groupData['admins'] ?? []);

      for (String participantUid in participants) {
        var userDoc =
            await _firestore.collection('users').doc(participantUid).get();
        if (userDoc.exists) {
          var userData = userDoc.data() as Map<String, dynamic>? ?? {};
          participantDetails.add({
            'uid': participantUid,
            'username': userData['username'] ?? '',
          });
        }
      }

      // Ensure the widget is still mounted before proceeding
      if (!context.mounted) return;
    } catch (e) {
      print('Error fetching group settings: $e');
    }
  }

  void _showGroupSettingsDialog(
      List<Map<String, dynamic>> participantDetails, List<String> admins) {
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Group Settings"),
          content: SizedBox(
            width:
                double.maxFinite, // Ensures it takes the maximum width allowed
            height: 300, // Set an appropriate height
            child: ListView.builder(
              itemCount: participantDetails.length,
              itemBuilder: (context, index) {
                String participantUid = participantDetails[index]['uid'];
                String username = participantDetails[index]['username'];

                return GestureDetector(
                  onLongPress: () {
                    // Show context menu when a participant's name is long-pressed
                    _showParticipantContextMenu(
                        participantUid, username, admins);
                  },
                  child: ListTile(
                    title: Text(username),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("Close"),
            ),
            // Add the "Add Participant" button
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog after action
                _addParticipantToGroup();
              },
              child: Text("Add Participant"),
            ),
          ],
        );
      },
    );
  }

  void _showParticipantContextMenu(
      String participantUid, String username, List<String> admins) {
    // Get the screen height and width using MediaQuery
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        screenWidth * 0.05, // Adjust the horizontal position as needed
        screenHeight - 150, // Position the menu near the bottom of the screen
        screenWidth * 0.05, // Adjust the horizontal position as needed
        0, // No vertical offset on the right side
      ),
      items: [
        // Option to make the participant an admin if they are not an admin
        if (!admins.contains(participantUid))
          PopupMenuItem(
            value: 'make_admin',
            child: Text('Make Admin'),
          ),
        // Option to remove admin privileges if the participant is an admin
        if (admins.contains(participantUid))
          PopupMenuItem(
            value: 'remove_admin',
            child: Text('Remove Admin'),
          ),
        // Option to remove the participant from the group
        PopupMenuItem(
          value: 'remove_participant',
          child: Text('Remove Participant'),
        ),
      ],
      elevation: 8.0,
    ).then((value) {
      // Handle the selected option from the context menu
      if (value == 'make_admin') {
        _makeAdmin(participantUid);
      } else if (value == 'remove_admin') {
        _removeAdmin(participantUid);
      } else if (value == 'remove_participant') {
        _removeParticipant(participantUid);
      }
    });
  }

  Future<void> _makeAdmin(String participantUid) async {
    try {
      bool confirm = await _showConfirmationDialog(
        'Promote to Admin',
        'Are you sure you want to promote this user to an admin?',
      );
      if (!confirm) return;

      await _firestore.collection('conversations').doc(conversationId).update({
        'admins': FieldValue.arrayUnion([participantUid]),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User promoted to Admin')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _removeAdmin(String participantUid) async {
    try {
      var groupDoc = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();
      var groupData = groupDoc.data()?.cast<String, dynamic>() ?? {};
      List<String> admins = List<String>.from(groupData['admins'] ?? []);

      if (admins.length == 1 && admins.contains(participantUid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('At least one admin must be present in the group')),
        );
        return;
      }

      bool confirm = await _showConfirmationDialog(
        'Remove Admin',
        'Are you sure you want to remove this user from admin role?',
      );
      if (!confirm) return;

      await _firestore.collection('conversations').doc(conversationId).update({
        'admins': FieldValue.arrayRemove([participantUid]),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User removed from Admin role')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _addParticipantToGroup() async {
    // Navigate to the ConnectionsScreen with isAddingParticipants flag as true
    var result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConnectionsScreen(
          isAddingParticipants: true,
          conversationId: widget.groupId, // Pass the flag
        ),
      ),
    );

    // If any users were selected
    if (result != null && result is List<String>) {
      List<String> selectedUsers = result;

      // Add the selected users to the group
      try {
        await _firestore
            .collection('conversations')
            .doc(widget.groupId)
            .update({
          'participants': FieldValue.arrayUnion(selectedUsers),
        });

        // Update the state with the new participants
        setState(() {
          widget.participantIds.addAll(selectedUsers); // Update the local state
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Participants added successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding participants: $e')),
        );
      }
    }
  }

  Future<void> _removeParticipant(String participantUid) async {
    try {
      var groupDoc = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();
      var groupData = groupDoc.data()?.cast<String, dynamic>() ?? {};
      List<String> admins = List<String>.from(groupData['admins'] ?? []);

      if (widget.currentUserUid == participantUid) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You cannot remove yourself from the group')),
        );
        return;
      }

      if (!admins.contains(widget.currentUserUid)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('You need admin privileges to remove a participant')),
        );
        return;
      }

      // Remove participant from participants array
      await _firestore.collection('conversations').doc(conversationId).update({
        'participants': FieldValue.arrayRemove([participantUid]),
      });

      // Remove participant from unreadMessages map
      await _firestore.collection('conversations').doc(conversationId).update({
        'unreadMessages': FieldValue.arrayRemove(
            [participantUid]), // Remove from unreadMessages map
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Participant removed')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  /// Helper function to show confirmation dialog
  Future<bool> _showConfirmationDialog(String title, String message) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
        onWillPop: () async {
          // Navigate to the HomePage when the back button is pressed
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomePage()),
          );
          return false; // Prevents the default back navigation
        },
        child: Scaffold(
          backgroundColor: AppColors.blackIndigoDark,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(
                kToolbarHeight), // Use the default AppBar height
            child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('conversations')
                    .doc(conversationId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return AppBar(
                      title: Text(widget.groupName,
                          style: TextStyle(color: Colors.white)),
                    );
                  }

                  // Get the entire document data
                  var groupData = snapshot.data!.data() as Map<String, dynamic>;

                  // Extract only the groupName (ignoring other fields)
                  String updatedGroupName =
                      groupData['groupName'] ?? widget.groupName;

                  return AppBar(
                    title: GestureDetector(
                      onTap: () {
                        // Call the method to show the group settings dialog when tapped
                        _showGroupSettingsDialog(participantDetails, admins);
                      },
                      child: Text(updatedGroupName,
                          style: TextStyle(color: Colors.white)),
                    ),
                    backgroundColor: AppColors.blackIndigoLight,
                  );
                }),
          ),
          body: Column(
            children: [
              Expanded(
                child: StreamBuilder(
                  stream: _firestore
                      .collection('conversations')
                      .doc(conversationId)
                      .collection('messages')
                      .orderBy('time', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    var messages = snapshot.data!.docs;
                    if (messages.isNotEmpty) {
                      Future.delayed(const Duration(milliseconds: 100), () {
                        _scrollToBottom();
                      });
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        var messageDoc = snapshot.data!.docs[index];
                        var message = messageDoc.data() as Map;
                        String messageId = messageDoc.id;
                        bool isSender =
                            message['senderId'] == widget.currentUserUid;
                        bool isEncrypted = message['isEncrypted'];
                        String messageContent = message['message'];
                        bool isRead = message['isRead'] ?? false;
                        bool isDeleted = message['isDeleted'] ?? false;
                        String displayMessage =
                            isDeleted ? 'Message Deleted' : messageContent;
                        String decryptedMessage = displayMessage;

                        if (!isSender && !isRead) {
                          _markMessageAsRead(messageId);
                        }

                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: StatefulBuilder(
                            builder: (context, setState) {
                              return GestureDetector(
                                onLongPress: () async {
                                  if (isEncrypted && !isDeleted) {
                                    bool authenticated =
                                        await _authenticateUser();
                                    if (authenticated) {
                                      setState(() {
                                        decryptedMessage =
                                            decryptMessage(messageContent);
                                      });
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Authentication failed')),
                                      );
                                    }
                                  }
                                },
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Row(
                                    mainAxisAlignment: isSender
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    children: [
                                      FutureBuilder<DocumentSnapshot>(
                                        future: isSender
                                            ? null
                                            : _firestore
                                                .collection('users')
                                                .doc(message['senderId'])
                                                .get(),
                                        builder: (context, snapshot) {
                                          String username =
                                              ""; // Default username for receiver
                                          if (!isSender &&
                                              snapshot.hasData &&
                                              snapshot.data != null &&
                                              snapshot.data!.exists) {
                                            var user = snapshot.data!.data()
                                                as Map<String, dynamic>?;
                                            username = user?['username'] ?? '';
                                          }

                                          return ConstrainedBox(
                                            constraints: BoxConstraints(
                                              maxWidth: MediaQuery.of(context)
                                                      .size
                                                      .width *
                                                  0.7, // Limit max width
                                            ),
                                            child: IntrinsicWidth(
                                              // Takes only required width
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8.0,
                                                        horizontal: 12.0),
                                                decoration: BoxDecoration(
                                                  color: isSender
                                                      ? AppColors
                                                          .blackIndigoLight
                                                      : const Color.fromARGB(
                                                          255, 46, 46, 46),
                                                  borderRadius:
                                                      BorderRadius.only(
                                                    topLeft:
                                                        const Radius.circular(
                                                            12.0),
                                                    topRight:
                                                        const Radius.circular(
                                                            12.0),
                                                    bottomLeft: isSender
                                                        ? const Radius.circular(
                                                            12.0)
                                                        : Radius.zero,
                                                    bottomRight: isSender
                                                        ? Radius.zero
                                                        : const Radius.circular(
                                                            12.0),
                                                  ),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    if (!isSender) // Show username inside the receiver's chat bubble
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                bottom: 4.0),
                                                        child: Text(
                                                          username,
                                                          style:
                                                              const TextStyle(
                                                            color:
                                                                Color.fromRGBO(
                                                                    121,
                                                                    134,
                                                                    203,
                                                                    1),
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize: 13,
                                                          ),
                                                        ),
                                                      ),
                                                    Row(
                                                      mainAxisSize: MainAxisSize
                                                          .min, // Prevents unnecessary stretching
                                                      children: [
                                                        if (isDeleted) ...[
                                                          const Icon(
                                                              Icons.delete,
                                                              color:
                                                                  Colors.grey,
                                                              size: 16),
                                                          const SizedBox(
                                                              width: 4),
                                                        ],
                                                        Flexible(
                                                          child: Text(
                                                            decryptedMessage,
                                                            textAlign:
                                                                TextAlign.start,
                                                            style: TextStyle(
                                                              color: isDeleted
                                                                  ? Colors.grey
                                                                  : Colors
                                                                      .white,
                                                              fontSize: 16,
                                                              fontStyle: isDeleted
                                                                  ? FontStyle
                                                                      .italic
                                                                  : FontStyle
                                                                      .normal,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    // Sent/Read Status
                                                    if (isSender)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 4.0),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .end,
                                                          children: [
                                                            // Display the Sent or Read status
                                                            Text(
                                                              isRead
                                                                  ? "✔✔ Read"
                                                                  : "✔ Sent",
                                                              style: TextStyle(
                                                                color: isRead
                                                                    ? Colors
                                                                        .blue
                                                                    : Colors
                                                                        .grey,
                                                                fontSize: 12,
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    Align(
                                                      alignment: isSender
                                                          ? Alignment
                                                              .bottomRight
                                                          : Alignment
                                                              .bottomLeft,
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 4.0),
                                                        child: Text(
                                                          formatTimestamp(DateTime
                                                              .fromMillisecondsSinceEpoch(
                                                                  message[
                                                                      'time'])),
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 12,
                                                                  color: Colors
                                                                      .grey),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
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
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10.0, vertical: 10.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        style: const TextStyle(color: Colors.white),
                        minLines: 1,
                        maxLines: 5,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.transparent,
                          hintText: 'Message',
                          hintStyle: const TextStyle(color: Colors.grey),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20.0),
                            borderSide: const BorderSide(
                                color: AppColors.blackIndigoLight),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 16.0, horizontal: 12.0),
                        ),
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onEditingComplete: () {
                          FocusScope.of(context).requestFocus(FocusNode());
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: GestureDetector(
                        onLongPressStart: (_) {
                          sendMessage(isEncrypted: true);
                        },
                        onLongPressEnd: (_) {},
                        child: FloatingActionButton(
                          onPressed: () => sendMessage(isEncrypted: false),
                          backgroundColor: AppColors.blackIndigoLight,
                          child: const Icon(Icons.send, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ));
  }
}
