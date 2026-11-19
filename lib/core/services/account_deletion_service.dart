import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'admin_service.dart';

typedef AccountDeletionData = Map<String, dynamic>;

abstract interface class AccountDeletionStore {
  Stream<AccountDeletionData> watchRequest(String uid);
  Stream<List<AccountDeletionData>> watchRequests(String status, {String? afterUid});
  Future<void> submitRequest(String uid, String reason);
  Future<void> enqueueReview(String uid, int revision, AccountDeletionData operation);
}

class FirestoreAccountDeletionStore implements AccountDeletionStore {
  FirestoreAccountDeletionStore(this.db);
  final FirebaseFirestore db;
  DocumentReference<AccountDeletionData> _request(String uid) => db.collection('account_deletion_requests').doc(uid);
  @override
  Stream<AccountDeletionData> watchRequest(String uid) => _request(uid).snapshots().map((s) => _normalize(s.data() ?? <String, dynamic>{}));
  @override
  Stream<List<AccountDeletionData>> watchRequests(String status, {String? afterUid}) {
    var query = db.collection('account_deletion_requests').where('status', isEqualTo: status)
      .orderBy(FieldPath.documentId).limit(30);
    if (afterUid != null) query = query.startAfter([afterUid]);
    return query.snapshots().map((s) => [
          for (final d in s.docs) {'uid': d.id, ..._normalize(d.data())},
        ]);
  }
  static AccountDeletionData _normalize(AccountDeletionData data) => {
    for (final entry in data.entries)
      entry.key: entry.value is Timestamp ? (entry.value as Timestamp).toDate() : entry.value,
  };
  @override
  Future<void> submitRequest(String uid, String reason) async {
    await db.runTransaction((tx) async {
      final ref = _request(uid); final current = (await tx.get(ref)).data();
      if (current != null && !['rejected', 'needs_clarification'].contains(current['status'])) {
        throw StateError('A deletion request is already being processed.');
      }
      if (current == null) {
        tx.set(ref, {'requesterUid': uid, 'requestedAt': FieldValue.serverTimestamp(), 'status': 'pending',
          'reason': reason, 'updatedAt': FieldValue.serverTimestamp(), 'revision': 1,
          'reviewedBy': null, 'reviewedAt': null, 'completionAt': null, 'processingStage': null, 'userMessage': null});
      } else {
        tx.update(ref, {'status': 'pending', 'reason': reason, 'revision': (current['revision'] as int) + 1,
          'updatedAt': FieldValue.serverTimestamp()});
      }
    });
  }
  @override
  Future<void> enqueueReview(String uid, int revision, AccountDeletionData operation) async {
    final ref = _request(uid).collection('operations').doc(); await ref.set(operation);
    final result = await ref.snapshots().firstWhere((s) => ['succeeded', 'failed'].contains(s.data()?['status']))
      .timeout(const Duration(seconds: 45));
    if (result.data()?['status'] == 'failed') throw StateError(result.data()?['errorMessage'] as String? ?? 'Review could not be processed.');
  }
}

class AccountDeletionService {
  AccountDeletionService({FirebaseFirestore? firestore, FirebaseAuth? auth, AccountDeletionStore? store})
      : auth = auth ?? FirebaseAuth.instance,
        store = store ?? FirestoreAccountDeletionStore(firestore ?? FirebaseFirestore.instance);
  final FirebaseAuth auth;
  final AccountDeletionStore store;
  Stream<AccountDeletionData> watchRequest(String uid) => store.watchRequest(uid);
  Stream<List<AccountDeletionData>> watchRequests(String status, {String? afterUid}) => store.watchRequests(status, afterUid: afterUid);
  Future<void> submit(String uid, String password, String reason) async {
    if (auth.currentUser?.uid != uid || password.isEmpty || reason.trim().length > 500) throw StateError('Confirm your current password and use at most 500 characters.');
    await AuthService(firebaseAuth: auth).reauthenticateForProfileChange(expectedUid: uid, password: password);
    if (auth.currentUser?.uid != uid) throw StateError('Your session changed. Sign in again.');
    await store.submitRequest(uid, reason.trim());
  }
  Future<void> review(String uid, int revision, String action, String note, String userMessage) async {
    if (note.trim().length > 1000 || userMessage.trim().length > 500 || (['reject', 'request_clarification'].contains(action) && userMessage.trim().isEmpty)) throw StateError('Add a message for rejection or clarification and check the text lengths.');
    final access = await AdminService(firebaseAuth: auth).readAccess(forceRefresh: true);
    if (access.status != AdminAccessStatus.allowed || access.uid == uid || auth.currentUser?.uid != access.uid) throw StateError('A different primary administrator must review this request.');
    await store.enqueueReview(uid, revision, {'actorUid': access.uid, 'action': action, 'expectedRevision': revision, 'note': note.trim(), 'userMessage': userMessage.trim(), 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()});
    if (auth.currentUser?.uid != access.uid) throw StateError('Admin session changed.');
  }
}

String deletionStatusLabel(String status) => switch (status) {
  'pending' => 'Request received — awaiting review', 'needs_clarification' => 'Clarification required',
  'approved' => 'Approved — deletion processing', 'rejected' => 'Request rejected',
  'completed' => 'Account deletion completed', _ => 'Not requested',
};
String deletionError(Object error) {
  if (error is AuthServiceException) return error.message;
  if (error is StateError) return error.message.toString();
  return 'Unable to confirm the result. Check the request status before trying again.';
}
