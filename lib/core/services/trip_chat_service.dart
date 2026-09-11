import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/trip_chat_message.dart';
import '../models/trip_post.dart';

class TripChatService {
  TripChatService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance, _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  String get uid => _auth.currentUser?.uid ?? (throw StateError('Please sign in to use trip chat.'));
  String newMessageId(String tripId) => _db.collection('trip_posts').doc(tripId).collection('messages').doc().id;
  Stream<TripPost> watchTrip(String tripId) {
    final actor = uid;
    return _db.collection('trip_posts').doc(tripId).snapshots().map((doc) {
      if (!doc.exists || uid != actor) throw StateError('This chat is no longer available.');
      final trip = TripPost.fromFirestore(doc);
      if (!TripChatMessage.canRead(trip, actor)) throw StateError('This chat is no longer available.');
      return trip;
    });
  }
  Stream<List<TripChatMessage>> watchMessages(TripPost trip) {
    final actor = uid;
    if (!TripChatMessage.canRead(trip, actor)) throw StateError('You cannot access this chat.');
    return messagesQuery(trip).snapshots().map((snapshot) {
        if (uid != actor) throw StateError('Your session changed.');
        return snapshot.docs.map((doc) => TripChatMessage.fromMap(doc.id, doc.data())).toList();
      });
  }
  Query<Map<String, dynamic>> messagesQuery(TripPost trip) {
    final actor = uid;
    if (!TripChatMessage.canRead(trip, actor)) throw StateError('You cannot access this chat.');
    Query<Map<String, dynamic>> query = _db.collection('trip_posts').doc(trip.id).collection('messages');
    if (actor != trip.creatorId) {
      query = query.where('assignmentDriverId', isEqualTo: actor);
    }
    return query.orderBy('createdAt');
  }
  Future<void> sendText({required String tripId, required String messageId, required String text, String? expectedAcceptedDriverId}) =>
    _send(tripId, messageId, 'text', TripChatMessage.validateText(text), null, null, expectedAcceptedDriverId);
  Future<void> sendLocation({required String tripId, required String messageId,
    required double latitude, required double longitude, String? expectedAcceptedDriverId}) {
    TripChatMessage.validateLocation(latitude, longitude);
    return _send(tripId, messageId, 'location', null, latitude, longitude, expectedAcceptedDriverId);
  }
  Future<void> _send(String tripId, String messageId, String type, String? text, double? lat, double? lng, String? expectedDriver) async {
    if (messageId.isEmpty || messageId.contains('/')) throw ArgumentError('Invalid message identifier.');
    final actor = uid;
    final parent = _db.collection('trip_posts').doc(tripId);
    final ref = parent.collection('messages').doc(messageId);
    // Transactions intentionally fail offline instead of queueing an unknown send.
    // The UI retains this ID/payload for an explicit retry after an uncertain result.
    await _db.runTransaction((tx) async {
      final tripDoc = await tx.get(parent);
      if (!tripDoc.exists) throw StateError('This trip is unavailable.');
      final trip = TripPost.fromFirestore(tripDoc);
      if (expectedDriver != null && trip.acceptedDriverId != expectedDriver) throw StateError('The trip assignment changed.');
      if (uid != actor || !TripChatMessage.canRead(trip, actor)) throw StateError('You cannot access this chat.');
      final role = actor == trip.creatorId ? 'creator' : 'driver';
      final existing = await tx.get(ref);
      if (existing.exists) {
        final message = TripChatMessage.fromMap(messageId, existing.data());
        if (message.isValid && message.tripId == tripId && message.senderId == actor &&
            message.assignmentDriverId == trip.acceptedDriverId &&
            message.senderRole == role && message.messageType == type && message.text == text &&
            message.latitude == lat && message.longitude == lng) {
          return;
        }
        throw StateError('This message identifier is already in use.');
      }
      if (!TripChatMessage.canWrite(trip, actor)) throw StateError('This chat is read-only.');
      if (uid != actor) throw StateError('Your session changed.');
      tx.set(ref, {...TripChatMessage(id: messageId, tripId: tripId, senderId: actor,
        senderRole: role, assignmentDriverId: trip.acceptedDriverId!,
        messageType: type, text: text, latitude: lat, longitude: lng).toFirestore(),
        'createdAt': FieldValue.serverTimestamp()});
    });
  }
}
