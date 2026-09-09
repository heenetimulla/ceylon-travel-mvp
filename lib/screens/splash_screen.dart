import '../app/app_text_styles.dart';
import '../app/app_colors.dart';
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
      backgroundColor: AppColors.ocean,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.travel_explore,
              size: 90,
              color: AppColors.surface,
            ),
            const SizedBox(height: 20),
            const Text('Ceylon Travel', style: AppTextStyles.hero),
            const SizedBox(height: 8),
            const Text(
              'Sri Lanka travel & driver community',
              style: AppTextStyles.onOcean,
            ),
            const SizedBox(height: 24),
            if (_sessionCheckFailed) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Unable to restore your session safely. Please try again.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.onOcean,
                ),
              ),
              TextButton(
                onPressed: _checkSession,
                child: const Text('Retry', style: AppTextStyles.onOcean),
              ),
            ] else
              const CircularProgressIndicator(color: AppColors.surface),
          ],
        ),
      ),
    );
  }
}
