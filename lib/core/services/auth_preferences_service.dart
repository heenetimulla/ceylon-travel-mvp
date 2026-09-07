import 'package:shared_preferences/shared_preferences.dart';

class AuthPreferencesService {
  const AuthPreferencesService();

  static const String _lastLoginEmailKey = 'auth.last_successful_login_email';

  Future<void> saveLastLoginEmail(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) return;
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _lastLoginEmailKey,
      normalizedEmail,
    );
    if (!saved) throw StateError('Unable to save login email.');
  }

  Future<String?> getLastLoginEmail() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_lastLoginEmailKey);
  }
}
