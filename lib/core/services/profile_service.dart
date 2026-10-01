import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/account_profile.dart';
import 'auth_service.dart';

abstract interface class ProfileSession {
  String? get uid;
  String? get email;
  Stream<String?> get changes;
  Future<void> reauthenticate(String uid, String password);
}

class AuthProfileSession implements ProfileSession {
  AuthProfileSession({AuthService? auth}) : _auth = auth ?? AuthService();
  final AuthService _auth;
  @override
  String? get uid => _auth.currentUser?.uid;
  @override
  String? get email => _auth.currentUser?.email;
  @override
  Stream<String?> get changes => _auth.authStateChanges.map((user) => user?.uid).distinct();
  @override
  Future<void> reauthenticate(String uid, String password) =>
    _auth.reauthenticateForProfileChange(expectedUid: uid, password: password);
}

abstract interface class ProfileStore {
  Future<Map<String, dynamic>?> load(String uid);
  Future<void> updateDetails(String uid, {required String fullName, required String city});
  Future<void> updatePhone(String uid, String phoneNumber);
}

class FirestoreProfileStore implements ProfileStore {
  FirestoreProfileStore({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;
  @override
  Future<Map<String, dynamic>?> load(String uid) async =>
    (await _db.collection('users').doc(uid).get()).data();
  @override
  Future<void> updateDetails(String uid, {required String fullName, required String city}) =>
    _db.collection('users').doc(uid).update({
      'fullName': fullName, 'city': city, 'updatedAt': FieldValue.serverTimestamp(),
    });
  @override
  Future<void> updatePhone(String uid, String phoneNumber) =>
    _db.collection('users').doc(uid).update({
      'phoneNumber': phoneNumber, 'updatedAt': FieldValue.serverTimestamp(),
    });
}

class ProfileService {
  ProfileService({ProfileSession? session, ProfileStore? store})
    : _session = session ?? AuthProfileSession(), _store = store ?? FirestoreProfileStore() {
    _uid = _session.uid;
    _subscription = _session.changes.listen((uid) {
      if (uid != _uid) {
        _invalidated = true;
      }
    });
  }
  final ProfileSession _session;
  final ProfileStore _store;
  late final String? _uid;
  late final StreamSubscription<String?> _subscription;
  bool _invalidated = false;
  Stream<String?> get sessionChanges => _session.changes;
  bool get hasSession => !_invalidated && _uid != null && _session.uid == _uid;
  String? get currentUid => hasSession ? _uid : null;
  void _checkSession() {
    if (!hasSession) {
      throw const ProfileException('Your session changed. Reopen settings after signing in.');
    }
  }
  Future<AccountProfile> load() async {
    _checkSession();
    final data = await _store.load(_uid!);
    _checkSession();
    if (data == null) {
      throw const ProfileException('Your profile is not available yet. Please try again.');
    }
    return AccountProfile(data, loginEmail: _session.email);
  }
  Future<void> updateDetails({required String fullName, required String city}) async {
    _checkSession();
    final error = validateName(fullName) ?? validateCity(city);
    if (error != null) {
      throw ProfileException(error);
    }
    await _store.updateDetails(_uid!, fullName: fullName.trim(), city: city.trim());
    _checkSession();
  }
  Future<void> changePhone({required String phoneNumber, required String password}) async {
    _checkSession();
    final error = validatePhone(phoneNumber);
    if (error != null) {
      throw ProfileException(error);
    }
    if (password.isEmpty) {
      throw const ProfileException('Enter your current password.');
    }
    // Every phone change re-authenticates, even if the original login was recent.
    await _session.reauthenticate(_uid!, password);
    _checkSession();
    await _store.updatePhone(_uid, phoneNumber.trim());
    _checkSession();
  }
  void dispose() {
    _invalidated = true;
    unawaited(_subscription.cancel());
  }
  static String? validateName(String? value) => value == null || value.trim().isEmpty
    ? 'Enter your full name.' : value.trim().length > 120 ? 'Use 120 characters or fewer.' : null;
  static String? validateCity(String? value) => (value?.trim().length ?? 0) > 100
    ? 'Use 100 characters or fewer.' : null;
  static String? validatePhone(String? value) => value == null || value.trim().isEmpty
    ? 'Phone number is required.'
    : !RegExp(r'^\+?[0-9][0-9 ()-]{5,24}$').hasMatch(value.trim())
      ? 'Enter a valid phone number, including the country code where needed.' : null;
}

class ProfileException implements Exception {
  const ProfileException(this.message);
  final String message;
}

String profileErrorMessage(Object error) {
  if (error is ProfileException) {
    return error.message;
  }
  if (error is AuthServiceException) {
    return error.message;
  }
  if (error is FirebaseException) {
    if (error.code == 'permission-denied') {
      return 'This change was not permitted. For a phone change, confirm your password again.';
    }
    if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
      return 'Unable to save right now. Check your connection and try again.';
    }
  }
  return 'Could not update your profile. Please try again.';
}
