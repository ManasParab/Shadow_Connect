import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shadow_connect/constants/colors.dart'; // Assuming your custom colors are in this file

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  _EditProfileScreenState createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _usernameController = TextEditingController();

  late User _user;
  String _currentUsername = '';

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser!;
    _fetchUserDetails();
  }

  // Fetch current username from Firestore
  Future<void> _fetchUserDetails() async {
    final userDoc = await _firestore.collection('users').doc(_user.uid).get();
    setState(() {
      _currentUsername = userDoc['username'] ?? 'No username';
      _usernameController.text =
          _currentUsername; // Initialize with current username
    });
  }

  // Function to update user profile
  void _updateProfile() async {
    final newUsername = _usernameController.text.trim();
    if (newUsername.isEmpty) {
      _showErrorDialog('Username cannot be empty');
      return;
    }

    if (newUsername == _currentUsername) {
      // If the username hasn't changed, just return
      Navigator.pop(context);
      return;
    }

    try {
      // 1. Create a new document with the new username in the 'usernames' collection
      await _firestore.collection('usernames').doc(newUsername).set({
        'uid': _user.uid,
      });

      // 2. Delete the old document with the current username
      await _firestore.collection('usernames').doc(_currentUsername).delete();

      // 3. Update the username in the 'users' collection
      await _firestore.collection('users').doc(_user.uid).update({
        'username': newUsername,
      });

      // If the username is updated successfully, navigate back
      Navigator.pop(context);
    } catch (e) {
      _showErrorDialog('Failed to update profile: $e');
    }
  }

  // Function to show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark, // Consistent background color
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: AppColors.blackIndigoDark, // Consistent app bar color
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: Column(
          children: [
            // Username input field
            TextField(
              controller: _usernameController,
              style: const TextStyle(
                  color: Colors.white), // Text color consistency
              decoration: InputDecoration(
                hintText: 'Username',
                labelStyle: const TextStyle(
                    color: Colors.white70), // Consistent label color
                border: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.deepPurple),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Save Changes Button
            ElevatedButton(
              onPressed: _updateProfile,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                backgroundColor: Colors.deepPurple, // Button color consistency
              ),
              child: const Text(
                'Save Changes',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
