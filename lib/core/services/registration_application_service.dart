import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'driver_administration_service.dart';
import '../models/registration_application.dart';

class RegistrationApplicationData {
  const RegistrationApplicationData(this.profile, this.application, this.operations, {this.history = const []});
  final Map<String, dynamic> profile;
  final Map<String, dynamic>? application;
  final List<Map<String, dynamic>> operations;
  final List<Map<String, dynamic>> history;
  int get revision => profile['applicationRevision'] is int ? profile['applicationRevision'] as int : 0;
  String get status => !profile.containsKey('registrationStatus') ? 'legacy'
    : profile['registrationStatus'] is String ? profile['registrationStatus'] as String : 'unavailable';
  bool get pendingOperation => operations.any((op) => op['status'] == 'pending');
}

class RegistrationApplicationService {
  RegistrationApplicationService({FirebaseAuth? auth, FirebaseFirestore? firestore}) : _authOverride = auth, _dbOverride = firestore;
  final FirebaseAuth? _authOverride;
  final FirebaseFirestore? _dbOverride;
  FirebaseAuth get auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseFirestore get db => _dbOverride ?? FirebaseFirestore.instance;
  Stream<String?> watchSession() => auth.idTokenChanges().map((u) => u?.uid);
  Future<String> access(String uid, bool admin) async {
    if (uid.isEmpty || uid.contains('/')) { throw ArgumentError('Invalid applicant.'); }
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Application access denied.');
    }
    if (admin) {
      final token = await user.getIdTokenResult();
      final claims = token.claims;
      if (claims == null || claims['admin'] != true) {
        throw StateError('Application access denied.');
      }
    } else if (user.uid != uid) {
      throw StateError('Application access denied.');
    }
    if (auth.currentUser?.uid != user.uid) { throw StateError('Your session changed.'); }
    return user.uid;
  }
  Future<RegistrationApplicationData> load(String uid, {bool admin = false}) async {
    final actor = await access(uid, admin);
    Map<String, dynamic>? profile;
    if (admin) {
      final docs = await db.collection('users').where(FieldPath.documentId, isEqualTo: uid).limit(1).get(const GetOptions(source: Source.server));
      profile = docs.docs.isEmpty ? null : docs.docs.single.data();
    } else { profile = (await db.collection('users').doc(uid).get(const GetOptions(source: Source.server))).data(); }
    if (profile == null) { throw StateError('Your profile is unavailable. Please finish registration or contact support.'); }
    if (!profile.containsKey('registrationStatus')) {
      if (await access(uid, admin) != actor) { throw StateError('Your session changed.'); }
      return RegistrationApplicationData(profile, null, []);
    }
    final app = await db.collection('registration_applications').doc(uid).get(const GetOptions(source: Source.server));
    final ops = await db.collection('users').doc(uid).collection('application_operations')
      .orderBy('createdAt', descending: true).limit(20).get(const GetOptions(source: Source.server));
    final history = await loadHistory(uid, admin: admin);
    if (await access(uid, admin) != actor) { throw StateError('Your session changed.'); }
    return RegistrationApplicationData(profile, app.data(), ops.docs.map((d) => d.data()).toList(), history: history);
  }
  Future<List<Map<String, dynamic>>> loadHistory(String uid, {bool admin = false, Map<String, dynamic>? after}) async {
    final actor = await access(uid, admin);
    Query<Map<String, dynamic>> query = db.collection('registration_applications').doc(uid).collection('history')
      .orderBy('createdAt', descending: true).orderBy(FieldPath.documentId, descending: true);
    if (after != null) { query = query.startAfter([after['createdAt'], after['operationId']]); }
    final page = await query.limit(20).get(const GetOptions(source: Source.server));
    if (await access(uid, admin) != actor) { throw StateError('Your session changed.'); }
    return page.docs.map((doc) => doc.data()).toList();
  }
  Future<Map<String, dynamic>> loadSubmission(String uid, int revision, {bool admin = false}) async {
    final actor = await access(uid, admin);
    if (revision < 1) { throw ArgumentError('Invalid application revision.'); }
    final doc = await db.collection('registration_applications').doc(uid).collection('submissions')
      .doc('$revision').get(const GetOptions(source: Source.server));
    if (await access(uid, admin) != actor) { throw StateError('Your session changed.'); }
    return doc.data() ?? (throw StateError('Submitted revision unavailable.'));
  }
  String newOperationId(String uid) => db.collection('users').doc(uid).collection('application_operations').doc().id;
  Future<void> perform(String uid, String action, Map<String, dynamic> payload,
    {required int revision, required String operationId, bool admin = false, String reason = ''}) async {
    final actor = await access(uid, admin);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(operationId) || revision < 0) {
      throw ArgumentError('Invalid application operation.');
    }
    if (!(admin ? ['approve', 'reject', 'request_correction'] : ['submit_application']).contains(action)) {
      throw ArgumentError('Unsupported application action.');
    }
    final ref = db.collection('users').doc(uid).collection('application_operations').doc(operationId);
    final command = {'actorUid': actor, 'action': action, 'payload': payload, 'expectedRevision': revision, 'reason': reason.trim()};
    final before = (await ref.get(const GetOptions(source: Source.server))).data();
    if (before == null) { await ref.set({...command, 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()}); }
    else if (!command.keys.every((key) => FirestoreDriverAdministrationDataSource.samePayload(command[key], before[key]))) {
      throw StateError('Refresh before changing a queued application.');
    }
    final result = await ref.snapshots(includeMetadataChanges: true)
      .where((d) => !d.metadata.isFromCache && d.exists && d.data()?['status'] != 'pending')
      .first.timeout(const Duration(seconds: 45));
    if (await access(uid, admin) != actor) { throw StateError('Your session changed.'); }
    if (result.data()?['status'] != 'succeeded') {
      throw DriverAdministrationException(result.data()?['errorMessage'] as String? ?? 'Application could not be processed. Refresh and retry.');
    }
  }
}

Future<void> requireOperationalAccount(FirebaseFirestore db, String uid, {Transaction? transaction}) async {
  final ref = db.collection('users').doc(uid);
  final snapshot = transaction == null ? await ref.get(const GetOptions(source: Source.server)) : await transaction.get(ref);
  final profile = snapshot.data();
  if (profile == null || !applicationOperational(profile)) { throw StateError(registrationAccessMessage); }
}
