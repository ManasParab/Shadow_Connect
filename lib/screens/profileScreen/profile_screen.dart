import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shadow_connect/constants/colors.dart';
import '../loginScreen/login_screen.dart';
import 'edit_profile_screen.dart'; // Assuming you have a screen for editing profile

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late User _user;
  String _username = '';
  String _email = '';
  String _uid = '';

  // Fetch user details from Firebase Firestore
  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser!;
    _email = _user.email ?? 'No email';
    _uid = _user.uid;
    _fetchUserDetails();
  }

  // Fetch the username from Firestore
  Future<void> _fetchUserDetails() async {
    final userDoc = await _firestore.collection('users').doc(_user.uid).get();
    setState(() {
      _username = userDoc['username'] ?? 'No username';
    });
  }

  // Function to handle logout
  void _logout(BuildContext context) async {
    bool confirmLogout = await _showLogoutDialog(context);
    if (confirmLogout) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  // Function to show logout confirmation dialog
  Future<bool> _showLogoutDialog(BuildContext context) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Logout"),
            content: const Text("Are you sure you want to logout?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text("Logout", style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Profile Container (replacing Card with Container)
            Container(
              width: double.infinity, // Set width to double.infinity
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2), // Shadow position
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Username
                  Text(
                    _username,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.blackIndigoDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Email
                  Text(
                    _email,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.blackIndigoDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // UID
                  Text(
                    'UID: $_uid',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.blackIndigoDark,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Edit Profile Button
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to Edit Profile screen
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const EditProfileScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      backgroundColor: Colors.deepPurple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text(
                      "Edit Profile",
                      style: TextStyle(fontSize: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Spacer to push the logout button to the bottom
            const Spacer(),

            // Logout Button
            ElevatedButton(
              onPressed: () => _logout(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text(
                "Logout",
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
