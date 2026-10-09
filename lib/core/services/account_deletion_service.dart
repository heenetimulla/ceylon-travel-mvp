import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_service.dart';
import 'admin_service.dart';

class AccountDeletionService {
  AccountDeletionService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : db = firestore ?? FirebaseFirestore.instance, auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  DocumentReference<Map<String, dynamic>> request(String uid) =>
    db.collection('account_deletion_requests').doc(uid);

  Future<void> submit(String uid, String password, String reason) async {
    if (auth.currentUser?.uid != uid || password.isEmpty || reason.trim().length > 500) {
      throw StateError('Confirm your current password and use at most 500 characters.');
    }
    await AuthService(firebaseAuth: auth).reauthenticateForProfileChange(expectedUid: uid, password: password);
    if (auth.currentUser?.uid != uid) { throw StateError('Your session changed. Sign in again.'); }
    await db.runTransaction((tx) async {
      final ref = request(uid);
      final current = (await tx.get(ref)).data();
      if (current != null && !['rejected', 'needs_clarification'].contains(current['status'])) {
        throw StateError('A deletion request is already being processed.');
      }
      if (current == null) {
        tx.set(ref, {
          'requesterUid': uid, 'requestedAt': FieldValue.serverTimestamp(),
          'status': 'pending', 'reason': reason.trim(), 'updatedAt': FieldValue.serverTimestamp(),
          'revision': 1, 'reviewedBy': null, 'reviewedAt': null, 'completionAt': null, 'processingStage': null, 'userMessage': null,
        });
      } else {
        tx.update(ref, {'status': 'pending', 'reason': reason.trim(),
          'revision': (current['revision'] as int) + 1, 'updatedAt': FieldValue.serverTimestamp()});
      }
    });
  }

  Future<void> review(String uid, int revision, String action, String note, String userMessage) async {
    if (note.trim().length > 1000 || userMessage.trim().length > 500 ||
        (['reject', 'request_clarification'].contains(action) && userMessage.trim().isEmpty)) {
      throw StateError('Add a message for rejection or clarification and check the text lengths.');
    }
    final access = await AdminService(firebaseAuth: auth).readAccess(forceRefresh: true);
    if (access.status != AdminAccessStatus.allowed || access.uid == uid ||
        auth.currentUser?.uid != access.uid) {
      throw StateError('A different primary administrator must review this request.');
    }
    final operation = request(uid).collection('operations').doc();
    await operation.set({
      'actorUid': access.uid, 'action': action, 'expectedRevision': revision,
      'note': note.trim(), 'userMessage': userMessage.trim(), 'status': 'pending', 'createdAt': FieldValue.serverTimestamp(),
    });
    final result = await operation.snapshots().firstWhere((snapshot) =>
      ['succeeded', 'failed'].contains(snapshot.data()?['status'])).timeout(const Duration(seconds: 45));
    if (auth.currentUser?.uid != access.uid) { throw StateError('Admin session changed.'); }
    if (result.data()?['status'] == 'failed') {
      throw StateError(result.data()?['errorMessage'] as String? ?? 'Review could not be processed.');
    }
  }
}

String deletionStatusLabel(String status) => switch (status) {
  'pending' => 'Request received — awaiting review',
  'needs_clarification' => 'Clarification required',
  'approved' => 'Approved — deletion processing',
  'rejected' => 'Request rejected',
  'completed' => 'Account deletion completed',
  _ => 'Not requested',
};
String deletionError(Object error) {
  if (error is AuthServiceException) { return error.message; }
  if (error is StateError) { return error.message.toString(); }
  return 'Unable to confirm the result. Check the request status before trying again.';
}
