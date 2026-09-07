import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../driver/driver_home_screen.dart';
import '../tourist/tourist_home_screen.dart';
import '../welcome_screen.dart';

Future<Widget> resolveStartupSession() async {
  final authService = AuthService();
  try {
    final user = await authService.authStateChanges.first.timeout(
      const Duration(seconds: 15),
    );
    if (user == null) return const WelcomeScreen();

    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 15));
    final data = profile.data();
    if (authService.currentUser?.uid == user.uid &&
        profile.exists &&
        data != null &&
        data['status'] == 'active') {
      switch (data['accountType']) {
        case 'tourist':
          return const TouristHomeScreen();
        case 'driver':
          return const DriverHomeScreen();
      }
    }
  } catch (_) {
    await authService.signOut();
    return const WelcomeScreen();
  }

  await authService.signOut();
  return const WelcomeScreen();
}

class LogoutButton extends StatefulWidget {
  const LogoutButton({super.key});

  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);
    final navigator = Navigator.of(context);
    try {
      await AuthService().signOut();
      if (!mounted) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Unable to log out. Please try again.')),
        );
    } finally {
      if (mounted) setState(() => _isLoggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _isLoggingOut ? 'Logging out...' : 'Logout',
      onPressed: _isLoggingOut ? null : _logout,
      icon: _isLoggingOut
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout),
    );
  }
}
