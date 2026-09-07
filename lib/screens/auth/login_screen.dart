import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/services/auth_preferences_service.dart';
import '../../core/services/auth_service.dart';
import '../driver/driver_home_screen.dart';
import '../tourist/tourist_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.authPreferences = const AuthPreferencesService(),
  });

  final AuthPreferencesService authPreferences;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool _isLoading = false;
  bool _emailEdited = false;

  @override
  void initState() {
    super.initState();
    _restoreLastLoginEmail();
  }

  Future<void> _restoreLastLoginEmail() async {
    try {
      final email = await widget.authPreferences.getLastLoginEmail();
      if (!mounted || _emailEdited || emailController.text.isNotEmpty) return;
      if (email != null) emailController.text = email;
    } catch (_) {
      return;
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return 'The email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many login attempts. Please wait and try again.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      default:
        return 'Unable to log in. Please try again later.';
    }
  }

  Future<void> _login() async {
    if (_isLoading) return;
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showError('Email is required.');
      return;
    }
    if (passwordController.text.isEmpty) {
      _showError('Password is required.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      final credential = await AuthService().signInWithEmailAndPassword(
        email: email,
        password: passwordController.text,
      );
      if (!mounted) return;
      passwordController.clear();
      final user = credential.user;
      if (user == null) {
        _showError('Unable to log in. Please try again.');
        return;
      }
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final data = profile.data();
      if (!profile.exists || data == null) {
        _showError(
          'Your account profile could not be found. Please contact support.',
        );
        return;
      }
      if (data['status'] != 'active') {
        _showError(
          'This account is currently unavailable. Please contact support.',
        );
        return;
      }
      final Widget homeScreen;
      switch (data['accountType']) {
        case 'tourist':
          homeScreen = const TouristHomeScreen();
          break;
        case 'driver':
          homeScreen = const DriverHomeScreen();
          break;
        default:
          _showError(
            'Your account type is not supported. Please contact support.',
          );
          return;
      }
      try {
        await widget.authPreferences.saveLastLoginEmail(email);
      } catch (_) {
        if (!mounted) return;
        _showError(
          'Signed in, but your email could not be remembered on this device.',
        );
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => homeScreen),
        (route) => false,
      );
    } on AuthServiceException catch (exception) {
      _showError(_authErrorMessage(exception.code));
    } on FirebaseException catch (exception) {
      _showError(
        exception.code == 'unavailable' || exception.code == 'deadline-exceeded'
            ? 'Unable to load your profile. Check your connection and try again.'
            : 'Unable to load your account profile. Please try again later.',
      );
    } catch (_) {
      _showError('Unable to log in. Please try again later.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Login to Ceylon Travel',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use your email address and password to access your account.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: emailController,
                    onChanged: (_) => _emailEdited = true,
                    autofillHints: const [AutofillHints.email],
                    enabled: !_isLoading,
                    autocorrect: false,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    autofillHints: const [AutofillHints.password],
                    enabled: !_isLoading,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Welcome back. Sign in to continue your journey.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _isLoading ? null : _login,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Login'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LoginInfoCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginInfoCard extends StatelessWidget {
  const LoginInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Color(0xFF0F766E)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Sign in with the email address you used to register your tourist or driver account.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
