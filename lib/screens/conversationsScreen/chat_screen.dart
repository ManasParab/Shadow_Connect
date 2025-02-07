import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

class ChatScreen extends StatefulWidget {
  final String uid;
  final String recipientUid;
  final String recipientUsername;

  const ChatScreen({
    super.key,
    required this.uid,
    required this.recipientUid,
    required this.recipientUsername,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuthentication = LocalAuthentication();

  bool _isSendingEncrypted = false;

  final _key = encrypt.Key.fromUtf8('32charlengthfor256bitkey12345678');
  final _iv = encrypt.IV.fromLength(16);

  String get conversationId {
    List<String> ids = [widget.uid, widget.recipientUid];
    ids.sort();
    return ids.join("_");
  }

  Future<void> _sendMessage(String message, bool isEncrypted) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    String messageToSend = message;

    if (isEncrypted) {
      messageToSend = encryptMessage(message);
    }

    DocumentReference conversationRef =
        _firestore.collection('conversations').doc(conversationId);

    CollectionReference messagesRef = conversationRef.collection('messages');

    Map<String, dynamic> messageData = {
      'messageId': timestamp.toString(),
      'message': messageToSend,
      'senderId': widget.uid,
      'time': timestamp,
      'isEncrypted': isEncrypted,
      'isDeleted': false,
      'isRead': false,
    };

    await messagesRef.add(messageData);

    // Update conversation document with last message and increment unread count
    await conversationRef.set({
      'participants': [widget.uid, widget.recipientUid],
      'lastMessage': messageToSend,
      'lastMessageTimestamp': timestamp,
      'unreadMessages': {widget.recipientUid: FieldValue.increment(1)}
    }, SetOptions(merge: true));

    Future.delayed(const Duration(milliseconds: 300), () {
      _scrollToBottom();
    });
  }

  Future<void> sendMessage() async {
    if (_controller.text.isNotEmpty) {
      String message = _controller.text.trim();
      if (message.isNotEmpty) {
        message = message[0].toUpperCase() + message.substring(1);
      }

      _controller.clear();

      _sendMessage(message, _isSendingEncrypted);

      _isSendingEncrypted = false;
    }
  }

  // Encryption function
  String encryptMessage(String message) {
    final key = encrypt.Key.fromUtf8('32charlengthfor256bitkey12345678');
    final iv = encrypt.IV.fromLength(16); // Generate a random IV
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));

    final encrypted = encrypter.encrypt(message, iv: iv);

    // Store IV along with the encrypted message (Base64 encoding both)
    final encodedIV = base64.encode(iv.bytes);
    final encodedMessage = encrypted.base64;

    return '$encodedIV:$encodedMessage';
  }

  Future<bool> _authenticateUser() async {
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

// Decryption function
  String decryptMessage(String encryptedMessage) {
    try {
      final key = encrypt.Key.fromUtf8('32charlengthfor256bitkey12345678');

      // Extract IV and the encrypted message
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      appBar: AppBar(
        title: Text(widget.recipientUsername,
            style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.blackIndigoLight,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
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

                // Mark unread messages as read
                for (var message in messages) {
                  var data = message.data() as Map<String, dynamic>;
                  if (data['senderId'] != widget.uid && !data['isRead']) {
                    message.reference.update({'isRead': true});
                    _firestore
                        .collection('conversations')
                        .doc(conversationId)
                        .set({
                      'unreadMessages': {widget.uid: 0}
                    }, SetOptions(merge: true));
                  }
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var message =
                        messages[index].data() as Map<String, dynamic>;
                    bool isSender = message['senderId'] == widget.uid;
                    bool isEncrypted = message['isEncrypted'];
                    String messageContent = message['message'];
                    bool isRead = message['isRead']; // Track read status
                    String decryptedMessage =
                        messageContent; // Default to original

                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: StatefulBuilder(
                        builder: (context, setState) {
                          return GestureDetector(
                            onLongPress: () async {
                              if (isEncrypted) {
                                bool authenticated = await _authenticateUser();
                                if (authenticated) {
                                  setState(() {
                                    decryptedMessage =
                                        decryptMessage(messageContent);
                                  });
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Authentication failed'),
                                    ),
                                  );
                                }
                              }
                            },
                            child: Row(
                              mainAxisAlignment: isSender
                                  ? MainAxisAlignment.end
                                  : MainAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8.0, horizontal: 12.0),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                            0.7, // Max 70% of screen width
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
                                  child: IntrinsicWidth(
                                    // Wrap content width
                                    child: Column(
                                      mainAxisSize: MainAxisSize
                                          .min, // Ensures no extra space
                                      crossAxisAlignment: isSender
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          decryptedMessage,
                                          textAlign: isSender
                                              ? TextAlign.end
                                              : TextAlign.start,
                                          style: TextStyle(
                                            color: isSender
                                                ? Colors.white
                                                : Colors.black,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (isSender)
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4.0),
                                              child: Text(
                                                isRead ? '✔✔ Read' : '✔ Sent',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isRead
                                                      ? Colors.blue
                                                      : Colors.grey,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
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
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
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
                      setState(() {
                        _isSendingEncrypted = true;
                      });
                    },
                    onLongPressEnd: (_) {
                      sendMessage();
                    },
                    onTap: () {
                      if (!_isSendingEncrypted) {
                        sendMessage();
                      }
                    },
                    child: FloatingActionButton(
                      onPressed: () {}, // No need to call sendMessage here
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
