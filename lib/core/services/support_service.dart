import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/support_request.dart';
import '../models/support_message.dart';
import '../models/readable_reference.dart';
import '../models/trip_post.dart';

class SupportService {
  SupportService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance, _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  String get uid => _auth.currentUser?.uid ?? (throw StateError('Please sign in.'));
  Future<Map<String, dynamic>> loadProfile() async {
    final actor = uid;
    final doc = await _db.collection('users').doc(actor).get(const GetOptions(source: Source.server));
    if (uid != actor) throw StateError('Your session changed.');
    return doc.data() ?? (throw StateError('Your profile is not available.'));
  }
  Stream<List<SupportRequest>> watchOwnRequests() {
    final actor = uid;
    return _db.collection('support_requests').where('userId', isEqualTo: actor).snapshots().map((s) {
      if (uid != actor) throw StateError('Your session changed.');
      return s.docs.map((d) => SupportRequest.fromMap(d.data())).toList()
        ..sort((a, b) => (b.lastMessageAt ?? DateTime(1970)).compareTo(a.lastMessageAt ?? DateTime(1970)));
    });
  }
  Stream<SupportRequest> watchRequest(String id) => _db.collection('support_requests').doc(id).snapshots().map((s) => SupportRequest.fromMap(s.data()!));
  Stream<List<SupportMessage>> watchMessages(String id) => _db.collection('support_requests').doc(id).collection('messages').orderBy('createdAt').snapshots().map((s) => s.docs.map((d) => SupportMessage.fromMap(d.data())).toList());
  Future<String> create({required String category, required String contactNumber,
    required String subject, required String message, String? subCategory,
    String? tripId, String? manualTripReference}) async {
    validateSupport(category: category, contactNumber: contactNumber, subject: subject, message: message);
    final actor = uid;
    final ref = _db.collection('support_requests').doc();
    final reference = generateReference('SUP');
    await _db.runTransaction((tx) async {
    final profile = (await tx.get(_db.collection('users').doc(actor))).data();
    if (profile == null || profile['status'] != 'active') throw StateError('Your active profile is required.');
    TripPost? trip;
    if (tripId != null) {
      trip = TripPost.fromFirestore(await tx.get(_db.collection('trip_posts').doc(tripId)));
      if (trip.status != 'completed' || (actor != trip.creatorId && actor != trip.acceptedDriverId)) throw StateError('Only participants can report a completed trip.');
      final categories = actor == trip.creatorId ? creatorComplaintCategories : driverComplaintCategories;
      if (category != 'complaint' || !categories.containsKey(subCategory)) throw ArgumentError('Choose a valid trip complaint category.');
    } else {
      if (subCategory != null) throw ArgumentError('A trip is required for that subcategory.');
      if ((manualTripReference ?? '').trim().isNotEmpty && category != 'complaint') throw ArgumentError('A manual trip reference is only available for complaints.');
      if ((manualTripReference ?? '').trim().length > 40) throw ArgumentError('Keep the trip reference within 40 characters.');
    }
    if (uid != actor) throw StateError('Your session changed.');
    final request = SupportRequest(id: ref.id, supportReference: reference,
      userId: actor, userRole: profile['accountType'] as String, userName: profile['fullName'] as String,
      contactNumber: contactNumber.trim(), category: category, subCategory: subCategory,
      tripId: trip?.id, tripReference: trip != null ? trip.tripReference : ((manualTripReference ?? '').trim().isEmpty ? null : manualTripReference!.trim().toUpperCase()),
      creatorId: trip?.creatorId, acceptedDriverId: trip?.acceptedDriverId,
      subject: subject.trim(), message: message.trim(), status: 'open');
    tx.set(ref, {...request.toFirestore(), 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(), 'lastMessageAt': FieldValue.serverTimestamp(), 'lastMessageId': null});
    });
    return ref.id;
  }
  Future<void> reply(String requestId, String message) async {
    final text = message.trim();
    if (text.isEmpty || text.length > 4000) throw ArgumentError('Write a reply of 1 to 4000 characters.');
    final actor = uid;
    final ref = _db.collection('support_requests').doc(requestId);
    final msg = ref.collection('messages').doc();
    await _db.runTransaction((tx) async {
      final request = (await tx.get(ref)).data();
      if (request == null || request['userId'] != actor || request['status'] == 'closed') throw StateError('You cannot reply to this request.');
      if (uid != actor) throw StateError('Your session changed.');
      tx.set(msg, {'id': msg.id, 'senderId': actor, 'senderRole': 'user', 'message': text, 'createdAt': FieldValue.serverTimestamp()});
      tx.update(ref, {'updatedAt': FieldValue.serverTimestamp(), 'lastMessageAt': FieldValue.serverTimestamp(), 'lastMessageId': msg.id});
    });
  }
}
