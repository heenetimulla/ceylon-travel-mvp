import 'package:firebase_auth/firebase_auth.dart';
import 'fcm_service.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  User? get currentUser => _firebaseAuth.currentUser;

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  Future<UserCredential> registerWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _runAuthAction(
      () => _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
  }

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) {
    return _runAuthAction(
      () => _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
  }

  Future<void> signOut() {
    return _runAuthAction(() async {
      final uid = _firebaseAuth.currentUser?.uid;
      if (uid != null) await FcmService.instance.beforeLogout(uid);
      try {
        await _firebaseAuth.signOut();
      } catch (_) {
        FcmService.instance.logoutFailed();
        rethrow;
      }
    });
  }

  /// Re-authenticates the same email/password account; never changes Auth's phone identity.
  Future<void> reauthenticateForProfileChange({
    required String expectedUid,
    required String password,
  }) => _runAuthAction(() async {
    final user = currentUser;
    if (user == null || user.uid != expectedUid) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    final email = user.email;
    if (email == null || !user.providerData.any((p) => p.providerId == 'password')) {
      throw FirebaseAuthException(code: 'unsupported-provider',
        message: 'Phone changes require email and password sign-in. Contact support.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    if (currentUser?.uid != expectedUid) {
      throw FirebaseAuthException(code: 'requires-recent-login');
    }
    // Refresh auth_time for the server-enforced recent authentication rule.
    await user.getIdTokenResult(true);
  });

  Future<T> _runAuthAction<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (exception) {
      throw AuthServiceException.fromFirebaseAuthException(exception);
    } catch (exception) {
      throw AuthServiceException(
        code: 'auth-service-error',
        message: 'Authentication failed. Please try again.',
        cause: exception,
      );
    }
  }
}

class AuthServiceException implements Exception {
  const AuthServiceException({
    required this.code,
    required this.message,
    this.cause,
  });

  factory AuthServiceException.fromFirebaseAuthException(
    FirebaseAuthException exception,
  ) {
    return AuthServiceException(
      code: exception.code,
      message: _messageForCode(exception),
      cause: exception,
    );
  }

  final String code;
  final String message;
  final Object? cause;

  static String _messageForCode(FirebaseAuthException exception) {
    switch (exception.code) {
      case 'email-already-in-use':
        return 'An account already exists for this email address.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'operation-not-allowed':
        return 'Email and password sign-in is not enabled.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'The email or password is incorrect.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'network-request-failed':
        return 'Check your internet connection and try again.';
      case 'requires-recent-login':
        return 'Please sign in again before changing your phone number.';
      default:
        return exception.message ?? 'Authentication failed. Please try again.';
    }
  }

  @override
  String toString() => 'AuthServiceException($code): $message';
}
