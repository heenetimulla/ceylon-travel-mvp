import 'package:firebase_auth/firebase_auth.dart';

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
    return _runAuthAction(_firebaseAuth.signOut);
  }

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
      default:
        return exception.message ?? 'Authentication failed. Please try again.';
    }
  }

  @override
  String toString() => 'AuthServiceException($code): $message';
}
