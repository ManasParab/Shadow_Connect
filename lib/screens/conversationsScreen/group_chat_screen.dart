import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'package:local_auth/local_auth.dart';
import 'package:intl/intl.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'package:flutter/services.dart';

class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final List<String> participantIds;
  final String groupName;
  final String currentUserUid;

  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.participantIds,
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

  Set<String> _selectedMessages = {};

  @override
  void initState() {
    super.initState();
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
        _firestore.collection('conversations').doc(conversationId);
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

    await messagesRef.add(messageData);

    await conversationRef.set({
      'participants': widget.participantIds,
      'lastMessage': messageToSend,
      'lastMessageTimestamp': timestamp,
      'totalMessages': FieldValue.increment(1),
    }, SetOptions(merge: true));

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

  void _showGroupSettingsDialog() {
    // Declare a local variable to hold the group name
    String newGroupName = widget.groupName;

    TextEditingController groupNameController =
        TextEditingController(text: newGroupName);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Group Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: groupNameController,
                decoration: const InputDecoration(
                  labelText: 'Group Name',
                ),
                onChanged: (value) {
                  // Update the local variable with the new value
                  newGroupName = value;
                },
              ),
              // Add other group settings options as needed
              SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // Update the groupName in Firebase under the conversations node
                      FirebaseFirestore.instance
                          .collection('conversations')
                          .doc(conversationId)
                          .update({
                        'groupName': newGroupName,
                      }).then((_) {
                        Navigator.pop(context);
                      }).catchError((error) {
                        // Handle error
                        print('Error updating group name: $error');
                      });
                    },
                    child: Text('Confirm'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: Text('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      appBar: PreferredSize(
        preferredSize:
            Size.fromHeight(kToolbarHeight), // Use the default AppBar height
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
                  onTap:
                      _showGroupSettingsDialog, // Your method to show group settings
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
                                bool authenticated = await _authenticateUser();
                                if (authenticated) {
                                  setState(() {
                                    decryptedMessage =
                                        decryptMessage(messageContent);
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Authentication failed')),
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
                                  if (!isSender) // Show username for non-sender (receiver)
                                    FutureBuilder<DocumentSnapshot>(
                                      future: _firestore
                                          .collection('users')
                                          .doc(message['senderId'])
                                          .get(),
                                      builder: (context, snapshot) {
                                        if (!snapshot.hasData ||
                                            snapshot.data == null ||
                                            !snapshot.data!.exists) {
                                          return const SizedBox
                                              .shrink(); // Handle missing data
                                        }

                                        var user = snapshot.data!.data()
                                            as Map<String, dynamic>?;
                                        String username =
                                            user?['username'] ?? 'Unknown';

                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          // Wrap username and message in a Row
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                left: 4.0,
                                              ),
                                              child: Text(
                                                username,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 14),
                                              ),
                                            ),
                                            // The message container now comes *after* the username
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8.0,
                                                      horizontal: 12.0),
                                              constraints: BoxConstraints(
                                                maxWidth: MediaQuery.of(context)
                                                        .size
                                                        .width *
                                                    0.7,
                                              ),
                                              decoration: BoxDecoration(
                                                color: isSender
                                                    ? AppColors.blackIndigoLight
                                                    : Colors.white,
                                                borderRadius: BorderRadius.only(
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
                                              child: Text(
                                                decryptedMessage,
                                                style: TextStyle(
                                                  color: isSender
                                                      ? Colors.white
                                                      : Colors.black,
                                                ),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    )
                                  else // If it's the sender, just show the message bubble
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8.0, horizontal: 12.0),
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                                0.7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSender
                                            ? AppColors.blackIndigoLight
                                            : Colors.white,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(12.0),
                                          topRight: const Radius.circular(12.0),
                                          bottomLeft: isSender
                                              ? const Radius.circular(12.0)
                                              : Radius.zero,
                                          bottomRight: isSender
                                              ? Radius.zero
                                              : const Radius.circular(12.0),
                                        ),
                                      ),
                                      child: Text(
                                        decryptedMessage,
                                        style: TextStyle(
                                          color: isSender
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                      ),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
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
                        borderSide:
                            const BorderSide(color: AppColors.blackIndigoLight),
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
    );
  }
}
