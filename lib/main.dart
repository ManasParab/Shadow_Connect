import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'constants/colors.dart';
import 'screens/conversationsScreen/conversations_screen.dart';
import 'screens/connectionsScreen/connections_screen.dart';
import 'screens/profileScreen/profile_screen.dart';
import 'screens/loginScreen/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/services.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings(
          '@mipmap/ic_launcher'); // Use your app icon.

  final InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
  );

  FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

  runApp(MyApp(flutterLocalNotificationsPlugin));
}

Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  var androidDetails = AndroidNotificationDetails(
    'channel_id',
    'Channel Name',
    channelDescription: 'Description of Channel',
    importance: Importance.max,
    priority: Priority.high,
    enableVibration: true,
  );

  var notificationDetails = NotificationDetails(android: androidDetails);

  if (message.notification?.title != null &&
      message.notification?.body != null) {
    await flutterLocalNotificationsPlugin.show(
      0,
      message.notification!.title,
      message.notification!.body,
      notificationDetails,
    );
  } else {
    print("🚨 Empty notification received, ignoring.");
  }

  print("Handling a background message: ${message.messageId}");
}

class MyApp extends StatefulWidget {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  const MyApp(this.flutterLocalNotificationsPlugin, {super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? deviceToken;

  void requestNotificationPermissions() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      print("Notifications are denied by the user.");
    }
  }

  @override
  void initState() {
    super.initState();
    getFCMToken();
    FirebaseMessaging.onMessage.listen(_foregroundMessageHandler);
    requestNotificationPermissions();
  }

  void getFCMToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    print("FCM Device Token: $token");

    // Store the FCM token in Firestore if the user is logged in
    if (token != null) {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get the user's UID
        String uid = user.uid;
        FirebaseFirestore firestore = FirebaseFirestore.instance;

        // Reference to the user's document in Firestore
        DocumentReference userRef = firestore.collection("users").doc(uid);

        // Fetch the current document
        DocumentSnapshot userDoc = await userRef.get();

        if (userDoc.exists) {
          // If the user document exists, fetch the current fcmTokens array
          List<dynamic> existingTokens =
              (userDoc.data() as Map<String, dynamic>)['fcmTokens'] ?? [];

          // Check if the current device's token already exists in the fcmTokens array
          if (!existingTokens.contains(token)) {
            // If the token doesn't exist, add it to the array
            await userRef.update({
              "fcmTokens": FieldValue.arrayUnion([token]),
            });
            print("FCM Token added to the user's document.");
          } else {
            print("FCM Token already exists for this device.");
          }
        } else {
          // If the document does not exist, create it with the fcmTokens array
          await userRef.set({
            "fcmTokens": [token], // Set the fcmTokens field initially
          });
          print("User document created with FCM token.");
        }
      }
    }
  }

  // Handle Foreground Message
  void _foregroundMessageHandler(RemoteMessage message) async {
    print("Message received in foreground: ${message.notification?.title}");
    print("Body: ${message.notification?.body}");

    await _showNotification(message);
  }

  Future<void> _showNotification(RemoteMessage message) async {
    var androidDetails = AndroidNotificationDetails(
      'channel_id',
      'Channel Name',
      channelDescription: 'Description of Channel',
      importance: Importance.max,
      priority: Priority.high,
      enableVibration: true,
    );

    var notificationDetails = NotificationDetails(android: androidDetails);

    int notificationId = DateTime.now()
        .millisecondsSinceEpoch
        .remainder(100000); // Generate unique ID

    await widget.flutterLocalNotificationsPlugin.show(
      notificationId,
      message.notification?.title,
      message.notification?.body,
      notificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FirebaseAuth.instance.currentUser != null
          ? const HomePage()
          : const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedIndex = 0;

  static List<Widget> pages = [
    const ConversationsScreen(),
    const ConnectionsScreen(),
    const ProfileScreen()
  ];

  void onItemTapped(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: pages[selectedIndex],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.blackIndigoDark,
        currentIndex: selectedIndex,
        onTap: onItemTapped,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(
              Icons.message,
              color: Colors.white,
            ),
            label: 'Conversations',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.mobile_friendly_rounded,
              color: Colors.white,
            ),
            label: 'Connections',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.person,
              color: Colors.white,
            ),
            label: 'Profile',
          ),
        ],
      ),
      backgroundColor: AppColors.blackIndigoDark,
      appBar: AppBar(
        title: const Text(
          "Shadow Connect",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: AppColors.blackIndigoDark,
        elevation: 0,
      ),
    );
  }
}
