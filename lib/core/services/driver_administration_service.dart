import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/driver_administration.dart';
import 'admin_service.dart';

abstract interface class DriverAdministrationDataSource {
  Future<DriverAdministration> load(String uid, bool admin);
  Future<List<DriverRecord>> page(String uid, String collection, DriverRecord after);
  String operationId(String uid);
  Future<void> enqueue(String uid, String operationId, Map<String, dynamic> command);
  Stream<DriverRecord> watchOperation(String uid, String operationId);
}

class FirestoreDriverAdministrationDataSource implements DriverAdministrationDataSource {
  FirestoreDriverAdministrationDataSource({FirebaseFirestore? firestore}) : _provided = firestore;
  final FirebaseFirestore? _provided;
  FirebaseFirestore get _db => _provided ?? FirebaseFirestore.instance;
  static const pageSize = 20;
  static bool samePayload(Object? before, Object? after) {
    if (before is Map && after is Map) {
      return before.length == after.length && before.keys.every((key) => after.containsKey(key) && samePayload(before[key], after[key]));
    }
    return before == after;
  }
  Future<List<DriverRecord>> _page(String uid, String collection, [DriverRecord? after]) async {
    Query<Map<String, dynamic>> query = _db.collection('users').doc(uid).collection(collection)
      .orderBy('createdAt', descending: true).orderBy(FieldPath.documentId, descending: true);
    if (after != null) {
      query = query.startAfter([after.data['createdAt'], after.id]);
    }
    final result = await query.limit(pageSize).get(const GetOptions(source: Source.server));
    return result.docs.map((doc) => DriverRecord(doc.id, doc.data())).toList();
  }
  @override
  Future<DriverAdministration> load(String uid, bool admin) async {
    final users = _db.collection('users');
    Map<String, dynamic>? profile;
    if (admin) {
      final result = await users.where(FieldPath.documentId, isEqualTo: uid).limit(1).get(const GetOptions(source: Source.server));
      profile = result.docs.isEmpty ? null : result.docs.single.data();
    } else {
      profile = (await users.doc(uid).get(const GetOptions(source: Source.server))).data();
    }
    if (profile == null) {
      throw StateError('Account unavailable.');
    }
    if (profile['accountType'] != 'driver') {
      return DriverAdministration(profile: profile);
    }
    final identity = await _db.collection('driver_verifications').doc(uid).get(const GetOptions(source: Source.server));
    return DriverAdministration(profile: profile,
      identity: identity.exists ? DriverRecord(uid, identity.data()!) : null,
      payments: await _page(uid, 'payments'),
      history: admin ? await _page(uid, 'admin_history') : [], operations: await _page(uid, 'driver_operations'));
  }
  @override
  Future<List<DriverRecord>> page(String uid, String collection, DriverRecord after) {
    if (!['payments', 'admin_history'].contains(collection)) {
      throw ArgumentError('Unsupported history.');
    }
    return _page(uid, collection, after);
  }
  @override
  String operationId(String uid) => _db.collection('users').doc(uid).collection('driver_operations').doc().id;
  @override
  Future<void> enqueue(String uid, String operationId, Map<String, dynamic> command) async {
    final ref = _db.collection('users').doc(uid).collection('driver_operations').doc(operationId);
    final previous = (await ref.get(const GetOptions(source: Source.server))).data();
    if (previous != null) {
      final before = previous['payload'], after = command['payload'] as Map<String, dynamic>;
      if (previous['actorUid'] != command['actorUid'] || previous['action'] != command['action'] ||
          previous['expectedRevision'] != command['expectedRevision'] || previous['reason'] != command['reason'] ||
          !samePayload(before, after)) {
        throw StateError('Operation conflict. Refresh before trying again.');
      }
      return;
    }
    await ref.set({...command, 'createdAt': FieldValue.serverTimestamp(), 'status': 'pending'});
  }
  @override
  Stream<DriverRecord> watchOperation(String uid, String operationId) => _db.collection('users').doc(uid)
    .collection('driver_operations').doc(operationId).snapshots(includeMetadataChanges: true)
    .where((snapshot) => !snapshot.metadata.isFromCache && snapshot.exists)
    .map((snapshot) => DriverRecord(snapshot.id, snapshot.data()!));
}

class DriverAdministrationService {
  DriverAdministrationService({AdminService? adminService, FirebaseAuth? firebaseAuth,
    DriverAdministrationDataSource? dataSource}) : _admin = adminService ?? AdminService(firebaseAuth: firebaseAuth),
      _providedAuth = firebaseAuth, _source = dataSource ?? FirestoreDriverAdministrationDataSource();
  final AdminService _admin;
  final FirebaseAuth? _providedAuth;
  final DriverAdministrationDataSource _source;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;
  Stream<String?> watchOwner() => _auth.idTokenChanges().map((user) => user?.uid);
  Future<String> access(String uid, bool admin) async {
    if (uid.isEmpty || uid.contains('/')) {
      throw ArgumentError('Invalid account.');
    }
    if (admin) {
      final access = await _admin.readAccess();
      if (access.status != AdminAccessStatus.allowed || access.uid == null) {
        throw StateError('Admin access required.');
      }
      return access.uid!;
    }
    if (_auth.currentUser?.uid != uid) {
      throw StateError('Sign in to your own driver account.');
    }
    return uid;
  }
  Future<DriverAdministration> load(String uid, {required bool admin}) async {
    final actor = await access(uid, admin);
    final data = await _source.load(uid, admin).timeout(const Duration(seconds: 25));
    if (await access(uid, admin) != actor) {
      throw StateError('Account session changed.');
    }
    return data;
  }
  Future<List<DriverRecord>> page(String uid, String collection, DriverRecord after, {required bool admin}) async {
    final actor = await access(uid, admin);
    if (collection == 'admin_history' && !admin) {
      throw StateError('Admin access required.');
    }
    final page = await _source.page(uid, collection, after).timeout(const Duration(seconds: 20));
    if (await access(uid, admin) != actor) {
      throw StateError('Account session changed.');
    }
    return page;
  }
  String newOperationId(String uid) => _source.operationId(uid);
  Future<void> perform(String uid, String action, Map<String, dynamic> payload,
      {required bool admin, required int revision, required String operationId, String reason = ''}) async {
    final actor = await access(uid, admin);
    final allowed = admin ? ['verify_identity', 'reject_identity', 'verify_payment', 'reject_payment', 'activate_membership', 'set_account_status']
      : ['submit_identity', 'request_payment', 'submit_payment'];
    if (!allowed.contains(action)) {
      throw ArgumentError('Unsupported action.');
    }
    if (operationId.isEmpty || operationId.contains('/')) {
      throw ArgumentError('Invalid operation.');
    }
    await _source.enqueue(uid, operationId, {'actorUid': actor, 'action': action, 'payload': payload,
      'expectedRevision': revision, 'reason': reason.trim()});
    final result = await _source.watchOperation(uid, operationId).timeout(const Duration(seconds: 40), onTimeout: (sink) {
      sink.addError(StateError('Operation is still queued. Refresh to check its result.'));
      sink.close();
    }).firstWhere((operation) => operation.text('status') != 'pending');
    if (await access(uid, admin) != actor) {
      throw StateError('Account session changed.');
    }
    if (result.text('status') != 'succeeded') {
      throw DriverAdministrationException(result.text('errorMessage', 'The operation failed. Refresh before trying again.'));
    }
  }
}

class DriverAdministrationException implements Exception {
  const DriverAdministrationException(this.message);
  final String message;
}
