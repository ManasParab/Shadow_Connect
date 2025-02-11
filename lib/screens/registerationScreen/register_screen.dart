import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'package:shadow_connect/main.dart';
import 'package:shadow_connect/screens/loginScreen/login_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _isPasswordVisible = false;
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  bool isLoading = false;

  Future<bool> _isUsernameTaken(String username) async {
    final doc = await firestore.collection("usernames").doc(username).get();
    return doc.exists;
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
          // If the user document exists, update the fcmTokens array
          await userRef.update({
            "fcmTokens": FieldValue.arrayUnion([token])
          });
        } else {
          // If the document does not exist, create it with the fcmTokens array
          await userRef.set({
            "fcmTokens": [token],
          });
        }
      }
    }
  }

  Future<void> _registerUser() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    String username = usernameController.text.trim();

    if (email.isEmpty || password.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All fields are required!",
              style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      bool usernameTaken = await _isUsernameTaken(username);
      if (usernameTaken) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Username already exists. Try a different one!",
                style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          isLoading = false;
        });
        return;
      }

      UserCredential userCredential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        String uid = userCredential.user!.uid;

        await firestore.collection("users").doc(uid).set({
          "uid": uid,
          "email": email,
          "username": username,
        });

        await firestore.collection("usernames").doc(username).set({
          "uid": uid,
        });

        // Call getFCMToken to store the FCM token in Firestore
        getFCMToken();

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = "Registration failed";

      if (e.code == 'email-already-in-use') {
        errorMessage = "Email is already in use";
      } else if (e.code == 'weak-password') {
        errorMessage = "Password should be at least 6 characters";
      } else if (e.code == 'invalid-email') {
        errorMessage = "Invalid email format";
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(errorMessage, style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: emailController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "Email",
                  hintStyle: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passwordController,
                obscuringCharacter: "*",
                obscureText: !_isPasswordVisible,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: "Password",
                  hintStyle: const TextStyle(fontSize: 16),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      setState(() {
                        _isPasswordVisible = !_isPasswordVisible;
                      });
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: usernameController,
                maxLength: 18,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: "Username",
                  hintStyle: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _registerUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Register",
                          style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const LoginScreen()),
                  );
                },
                child: const Text(
                  "Already have an account? Login",
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
