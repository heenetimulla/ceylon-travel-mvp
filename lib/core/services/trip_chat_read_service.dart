import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/trip_chat_message.dart';
import '../models/trip_post.dart';
import 'registration_application_service.dart';

/// Private per-recipient read cursor. Messages and assignment ownership stay immutable.
class TripChatReadService {
  TripChatReadService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance, _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  String get uid => _auth.currentUser?.uid ?? (throw StateError('Please sign in.'));

  static bool isUnread(Map<String, dynamic>? message, Map<String, dynamic>? cursor,
      String actor, String driver) {
    if (message == null || message['senderId'] == actor || message['assignmentDriverId'] != driver ||
        message['createdAt'] is! Timestamp) { return false; }
    return cursor?['assignmentDriverId'] != driver || cursor?['lastReadAt'] is! Timestamp ||
      (message['createdAt'] as Timestamp).compareTo(cursor!['lastReadAt'] as Timestamp) > 0;
  }

  Stream<bool> watchUnread(TripPost trip) {
    final actor = uid;
    if (!TripChatMessage.hasCurrentAssignment(trip, actor)) { return Stream.value(false); }
    final driver = trip.acceptedDriverId!;
    final other = actor == trip.creatorId ? driver : trip.creatorId;
    final parent = _db.collection('trip_posts').doc(trip.id);
    final latest = parent.collection('messages').where('assignmentDriverId', isEqualTo: driver)
      .where('senderId', isEqualTo: other).orderBy('createdAt', descending: true).limit(1);
    late StreamController<bool> output;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? messages;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? reads;
    Map<String, dynamic>? message, cursor;
    bool messagesReady = false, readsReady = false;
    void emit() {
      if (!output.isClosed && messagesReady && readsReady) {
        output.add(_auth.currentUser?.uid == actor && isUnread(message, cursor, actor, driver));
      }
    }
    void failed(Object error, StackTrace trace) {
      messagesReady = false; readsReady = false; message = null;
      if (!output.isClosed) { output.add(false); output.addError(error, trace); }
    }
    output = StreamController<bool>(onListen: () {
      messages = latest.snapshots().listen((snapshot) {
        message = snapshot.docs.isEmpty ? null : snapshot.docs.first.data(); messagesReady = true; emit();
      }, onError: failed);
      reads = parent.collection('chat_reads').doc(actor).snapshots().listen((snapshot) {
        cursor = snapshot.data(); readsReady = true; emit();
      }, onError: failed);
    }, onCancel: () async { await messages?.cancel(); await reads?.cancel(); });
    return output.stream.distinct();
  }

  /// Acknowledge only a message actually shown, never a wall-clock cutoff that
  /// could swallow an incoming message racing with opening the screen.
  Future<void> markRead(TripPost expected, String messageId) async {
    final actor = uid;
    if (messageId.isEmpty || messageId.contains('/')) { throw ArgumentError('Invalid message.'); }
    final parent = _db.collection('trip_posts').doc(expected.id);
    final cursorRef = parent.collection('chat_reads').doc(actor);
    await _db.runTransaction((tx) async {
      await requireOperationalAccount(_db, actor, transaction: tx);
      final trip = TripPost.fromFirestore(await tx.get(parent));
      if (!TripChatMessage.hasCurrentAssignment(trip, actor) || trip.acceptedDriverId != expected.acceptedDriverId) {
        throw StateError('The trip assignment changed.');
      }
      final message = (await tx.get(parent.collection('messages').doc(messageId))).data();
      final cursor = (await tx.get(cursorRef)).data();
      if (message == null || message['assignmentDriverId'] != trip.acceptedDriverId ||
          message['senderId'] != (actor == trip.creatorId ? trip.acceptedDriverId : trip.creatorId) ||
          message['createdAt'] is! Timestamp) { throw StateError('This message cannot be marked read.'); }
      if (uid != actor) { throw StateError('Your session changed.'); }
      if (!isUnread(message, cursor, actor, trip.acceptedDriverId!)) { return; }
      tx.set(cursorRef, {'assignmentDriverId': trip.acceptedDriverId,
        'lastReadMessageId': messageId, 'lastReadAt': message['createdAt'], 'updatedAt': FieldValue.serverTimestamp()});
    });
  }
}
