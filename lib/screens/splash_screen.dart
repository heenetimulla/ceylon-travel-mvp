import 'dart:async';

import 'package:flutter/material.dart';

import 'auth/session_navigation.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.resolveSession});

  final Future<Widget> Function()? resolveSession;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _sessionCheckFailed = false;

  @override
  void initState() {
    super.initState();

    _timer = Timer(const Duration(seconds: 2), _checkSession);
  }

  Future<void> _checkSession() async {
    if (!mounted) return;
    setState(() => _sessionCheckFailed = false);
    try {
      final destination =
          await (widget.resolveSession ?? resolveStartupSession)();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => destination),
        (route) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sessionCheckFailed = true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0F766E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.travel_explore, size: 90, color: Colors.white),
            const SizedBox(height: 20),
            const Text(
              'Ceylon Travel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sri Lanka travel & driver community',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            if (_sessionCheckFailed) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Unable to restore your session safely. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: _checkSession,
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ] else
              const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
