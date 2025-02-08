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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: FirebaseAuth.instance.currentUser != null
          ? const HomePage()
          : const LoginScreen(),
      debugShowCheckedModeBanner: false, // Optionally disable debug banner
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
        child: pages[
            selectedIndex], // Ensure the selected screen fills the entire body
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
        elevation: 0, // Remove any elevation from the app bar
      ),
    );
  }
}