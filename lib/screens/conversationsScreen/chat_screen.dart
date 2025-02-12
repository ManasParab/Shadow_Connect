import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'connections_screen.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

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
  Map<String, bool> messageTranslationState = {};
  Map<String, String> translatedMessages =
      {}; // Map to store translated messages

  String selectedLanguage = 'English';
  Map<String, String> supportedLanguages = {
    'English': 'en',
    'Spanish': 'es',
    'French': 'fr',
    'German': 'de',
    'Hindi': 'Hn',
    'Marathi': 'Ma',
  };
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalAuthentication _localAuthentication = LocalAuthentication();
  bool _isSendingEncrypted = false;
  bool _isBulkActionMode = false; // Check if bulk action mode is enabled
  final _key = encrypt.Key.fromUtf8('32charlengthfor256bitkey12345678');
  final _iv = encrypt.IV.fromLength(16);

  Set<String> _selectedMessages = {}; // Keep track of selected messages
  bool _hasScrolledToBottom = false; // Flag to track if scrolled to bottom
  bool _isAuthenticating = false; // Added for authentication check
  double _dragOffset = 0.0; // Variable to track the drag offset

  @override
  void initState() {
    super.initState();
    // Call _scrollToBottom when the conversation is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  String get conversationId {
    List ids = [widget.uid, widget.recipientUid];
    ids.sort();
    return ids.join("_");
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
      'senderId': widget.uid,
      'recipientId': widget.recipientUid,
      'time': timestamp,
      'isEncrypted': isEncrypted,
      'isDeleted': false,
      'isRead': false,
      'isForwarded': false,
    };

    await messagesRef.add(messageData);

    await conversationRef.set({
      'participants': [widget.uid, widget.recipientUid],
      'lastMessage': messageToSend,
      'lastMessageTimestamp': timestamp,
      'unreadMessages': {
        widget.recipientUid: FieldValue.increment(1),
        widget.uid: 0,
      },
      'totalMessages': FieldValue.increment(1), // Increment totalMessages
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

    await _firestore.collection('conversations').doc(conversationId).update({
      'unreadMessages.${widget.uid}': FieldValue.increment(-1),
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

  Future<String> translateMessage(
    String messageContent,
    String targetLanguage,
    String messageId, // pass the message ID to update its state
  ) async {
    // Set translation state to true (translation in progress)
    setState(() {
      messageTranslationState[messageId] = true;
    });

    final supportedLanguages = {
      "Spanish": TranslateLanguage.spanish,
      "French": TranslateLanguage.french,
      "German": TranslateLanguage.german,
      "Chinese": TranslateLanguage.chinese,
      "Hindi": TranslateLanguage.hindi,
      "Marathi": TranslateLanguage.marathi
    };

    // Check if the selected language is valid
    if (!supportedLanguages.containsKey(targetLanguage)) {
      setState(() {
        messageTranslationState[messageId] = false; // Reset on error
      });
      return "Error: Unsupported language";
    }

    final targetTranslateLanguage = supportedLanguages[targetLanguage]!;

    // Initialize the translator
    final onDeviceTranslator = OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: targetTranslateLanguage,
    );

    try {
      // Perform translation
      String translatedMessage =
          await onDeviceTranslator.translateText(messageContent);

      // Update the translated message in the map
      setState(() {
        translatedMessages[messageId] = translatedMessage;
        messageTranslationState[messageId] =
            false; // Reset once translation is done
      });

      return translatedMessage;
    } catch (e) {
      setState(() {
        messageTranslationState[messageId] = false; // Reset on error
      });
      return "Error: ${e.toString()}";
    } finally {
      await onDeviceTranslator.close();
    }
  }

  // Delete selected messages
  Future<void> _deleteMessages() async {
    for (var messageId in _selectedMessages) {
      await _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId)
          .delete();

      // Decrement the totalMessages field
      await _firestore.collection('conversations').doc(conversationId).update({
        'totalMessages': FieldValue.increment(-1),
      });

      // Check if totalMessages is 0, then delete the conversation document
      DocumentSnapshot conversationSnapshot = await _firestore
          .collection('conversations')
          .doc(conversationId)
          .get();

      // Cast data as Map<String, dynamic> before accessing the 'totalMessages' field
      Map<String, dynamic> data =
          conversationSnapshot.data() as Map<String, dynamic>;
      int totalMessages = data['totalMessages'] ?? 0;

      if (totalMessages == 0) {
        await _firestore
            .collection('conversations')
            .doc(conversationId)
            .delete();
      }
    }

    setState(() {
      _selectedMessages.clear();
      _isBulkActionMode = false; // Exit bulk mode
    });
  }

  // Toggle message selection
  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessages.contains(messageId)) {
        _selectedMessages.remove(messageId);
      } else {
        _selectedMessages.add(messageId);
      }
      _isBulkActionMode = _selectedMessages.isNotEmpty;
    });
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

  // Handle menu item selections
  // Handle menu item selections (for bulk actions)
  void _handleMenuSelection(String value) {
    switch (value) {
      case 'clear':
        _clearChat();
        break;
      case 'mute':
        _muteNotifications();
        break;
      case 'delete':
        _deleteMessages();
        break;
      case 'forward':
        _forwardMessages();
        break;
      case 'block':
        _blockUser();
        break;
    }
  }

  void _clearChat() {
    // Add your logic to clear chat messages
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat cleared!')),
    );
  }

  void _muteNotifications() {
    // Add your logic to mute notifications
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifications muted!')),
    );
  }

  void _blockUser() {
    _firestore.collection('users').doc(widget.uid).update({
      'blockedUsers': FieldValue.arrayUnion([widget.recipientUid]),
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('User blocked')));
  }

  void _forwardMessages() {
    // Get the content of the selected message. Here, assuming the selected message
    // is the one that has been long-pressed or toggled.
    String messageToForward = '';

    // Loop through selected messages to get their content
    for (var messageId in _selectedMessages) {
      var messageDoc = _firestore
          .collection('conversations')
          .doc(conversationId)
          .collection('messages')
          .doc(messageId);

      messageDoc.get().then((docSnapshot) {
        if (docSnapshot.exists) {
          var message = docSnapshot.data() as Map<String, dynamic>;
          messageToForward = message['message'] ?? '';

          if (messageToForward.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    ConnectionsScreen(messageToForward: messageToForward),
              ),
            );
          }
        }
      });
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
        actions: [
          if (_isBulkActionMode) ...[
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteMessages,
            ),
            IconButton(
              icon: const Icon(Icons.forward),
              onPressed: _forwardMessages,
            ),
          ],
          PopupMenuButton<String>(
            onSelected: _handleMenuSelection,
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                  value: 'clear', child: Text('Clear Chat')),
              const PopupMenuItem<String>(
                  value: 'mute', child: Text('Mute Notifications')),
              const PopupMenuItem<String>(
                  value: 'delete', child: Text('Delete')),
              const PopupMenuItem<String>(
                  value: 'forward', child: Text('Forward')),
              const PopupMenuItem<String>(
                  value: 'block', child: Text('Block User')),
            ],
          ),
        ],
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
                if (messages.isNotEmpty && !_hasScrolledToBottom) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _scrollToBottom();
                    _hasScrolledToBottom = true; // Set the flag to true
                  });
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    var messageDoc = snapshot.data!.docs[index];
                    var message = messageDoc.data() as Map;
                    String messageId = messageDoc.id;
                    bool isSender = message['senderId'] == widget.uid;
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
                            onHorizontalDragUpdate: (details) {
                              // Restrict dragging direction based on sender
                              if (isSender) {
                                // Allow dragging only from right to left
                                if (_dragOffset + details.delta.dx <= 0) {
                                  setState(() {
                                    _dragOffset += details
                                        .delta.dx; // Move left for sender
                                  });
                                }
                              } else {
                                // Allow dragging only from left to right
                                if (_dragOffset + details.delta.dx >= 0) {
                                  setState(() {
                                    _dragOffset += details
                                        .delta.dx; // Move right for receiver
                                  });
                                }
                              }
                            },
                            onHorizontalDragEnd: (details) async {
                              // Reset the drag offset when the drag ends
                              if (_dragOffset != 0) {
                                if (isEncrypted) {
                                  // Authenticate user if the message is encrypted
                                  if (!_isAuthenticating) {
                                    _isAuthenticating =
                                        true; // Set the flag to true
                                    bool authenticated =
                                        await _authenticateUser();
                                    if (authenticated) {
                                      String decryptedMessage =
                                          decryptMessage(messageContent);
                                      if (decryptedMessage.isNotEmpty) {
                                        // Translate the decrypted message
                                        String translatedMessage =
                                            await translateMessage(
                                                decryptedMessage,
                                                selectedLanguage,
                                                messageId);
                                        setState(() {
                                          // Update the message bubble with the translated message
                                          messageContent =
                                              translatedMessage; // Update the message content
                                        });
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content:
                                                  Text('Decryption failed')),
                                        );
                                      }
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Authentication failed')),
                                      );
                                    }
                                    _isAuthenticating =
                                        false; // Reset the flag after authentication attempt
                                  }
                                } else {
                                  // If not encrypted, just translate the message
                                  String translatedMessage =
                                      await translateMessage(messageContent,
                                          selectedLanguage, messageId);
                                  setState(() {
                                    // Update the message bubble with the translated message
                                    messageContent =
                                        translatedMessage; // Update the message content
                                  });
                                }
                                // Reset the drag offset after processing
                                setState(() {
                                  _dragOffset = 0.0;
                                });
                              }
                            },
                            onLongPress: () async {
                              if (isEncrypted && !isDeleted) {
                                if (!_isAuthenticating) {
                                  // Check if already authenticating
                                  _isAuthenticating =
                                      true; // Set the flag to true
                                  bool authenticated =
                                      await _authenticateUser();
                                  if (authenticated) {
                                    String decryptedMessage =
                                        decryptMessage(messageContent);
                                    if (decryptedMessage.isNotEmpty) {
                                      // Update the message bubble with the decrypted message
                                      setState(() {
                                        messageContent =
                                            decryptedMessage; // Update the message content
                                      });
                                    } else {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text('Decryption failed')),
                                      );
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Authentication failed')),
                                    );
                                  }
                                  _isAuthenticating =
                                      false; // Reset the flag after authentication attempt
                                }
                              }
                            },
                            onDoubleTap: () =>
                                _toggleMessageSelection(messageId),
                            onTap: () {
                              if (_selectedMessages.isEmpty) {
                                // Perform any default action if no message is selected.
                              } else {
                                _toggleMessageSelection(messageId);
                              }
                            },
                            child: Transform.translate(
                              offset: Offset(
                                  _dragOffset, 0), // Apply the drag offset
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Row(
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
                                                0.7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSender
                                            ? AppColors.blackIndigoLight
                                            : const Color.fromARGB(
                                                255, 46, 46, 46),
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
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: isSender
                                              ? CrossAxisAlignment.end
                                              : CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isDeleted) ...[
                                                  const Icon(Icons.delete,
                                                      color: Colors.grey,
                                                      size: 16),
                                                  const SizedBox(width: 4),
                                                ],
                                                Flexible(
                                                  child: Stack(
                                                    children: [
                                                      if (messageTranslationState[
                                                              messageId] ==
                                                          true) // Show loading indicator
                                                        const Align(
                                                          alignment: Alignment
                                                              .centerRight,
                                                          child:
                                                              CircularProgressIndicator(
                                                            color: Colors.blue,
                                                          ),
                                                        ),
                                                      Text(
                                                        translatedMessages[
                                                                messageId] ??
                                                            messageContent, // Use the updated message content
                                                        textAlign: isSender
                                                            ? TextAlign.end
                                                            : TextAlign.start,
                                                        style: TextStyle(
                                                          color: isDeleted
                                                              ? Colors.grey
                                                              : Colors.white,
                                                          fontSize: 16,
                                                          fontStyle: isDeleted
                                                              ? FontStyle.italic
                                                              : FontStyle
                                                                  .normal,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (isSender)
                                              Align(
                                                alignment:
                                                    Alignment.bottomRight,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4.0),
                                                  child: Text(
                                                    isRead
                                                        ? '✔✔ Read'
                                                        : '✔ Sent',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isRead
                                                          ? Colors.blue
                                                          : Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            Align(
                                              alignment: isSender
                                                  ? Alignment.bottomRight
                                                  : Alignment.bottomLeft,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 4.0),
                                                child: Text(
                                                  formatTimestamp(DateTime
                                                      .fromMillisecondsSinceEpoch(
                                                          message['time'])),
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey),
                                                ),
                                              ),
                                            ),
                                          ],
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
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 8.0),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: MediaQuery.of(context).size.width),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: DropdownButton<String>(
                      value: selectedLanguage,
                      isExpanded: true,
                      items: supportedLanguages.keys.map((String language) {
                        return DropdownMenuItem<String>(
                          value: language,
                          child: Text(language),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedLanguage = newValue!;
                        });
                      },
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize
                        .min, // Ensures the row shrinks to fit its children
                    children: [
                      Flexible(
                        fit: FlexFit
                            .loose, // Allows the TextField to use only the space it needs
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
                            onPressed: () =>
                                sendMessage(isEncrypted: _isSendingEncrypted),
                            backgroundColor: AppColors.blackIndigoLight,
                            child: const Icon(Icons.send, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
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
