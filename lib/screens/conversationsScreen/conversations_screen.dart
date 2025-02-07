import 'package:flutter/material.dart';
import 'package:shadow_connect/constants/colors.dart';
import 'connections_screen.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.blackIndigoDark,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to the connections screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ConnectionsScreen(),
            ),
          );
        },
        backgroundColor: AppColors.Indigo,
        child: const Icon(
          Icons.add,
          color: Colors.white,
        ),
      ),
    );
  }
}
