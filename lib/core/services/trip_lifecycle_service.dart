import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/trip_post.dart';
import '../models/trip_lifecycle.dart';
import '../models/user_reputation.dart';

class TripLifecycleService {
  TripLifecycleService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance,
      _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  String get uid => _auth.currentUser?.uid ?? (throw StateError('Please sign in.'));
  Stream<TripPost> watchTrip(String id) {
    final actor = uid;
    return _db.collection('trip_posts').doc(id).snapshots().map((snapshot) {
      if (_auth.currentUser?.uid != actor) throw StateError('Your session changed.');
      final trip = TripPost.fromFirestore(snapshot);
      if (actor != trip.creatorId && actor != trip.acceptedDriverId) throw StateError('You no longer have access to this trip.');
      return trip;
    });
  }
  Future<void> requestStart(String id) => _request(id, true);
  Future<void> requestEnd(String id) => _request(id, false);
  Future<void> confirmStart(String id) => _transition(id, LifecycleAction.confirmStart);
  Future<void> confirmEnd(String id) => _transition(id, LifecycleAction.confirmEnd);

  Future<void> _request(String id, bool start) async {
    final actor = uid;
    final ref = _db.collection('trip_posts').doc(id);
    final anchor = ref.collection('lifecycle_requests').doc(start ? 'start' : 'end');
    // Server-time anchor, locked once the requested lifecycle state is published.
    // Retry requestStart/requestEnd after interruption to refresh a stale anchor.
    // Publishing the parent request triggers backend scheduling; no client auto writer.
    await _db.runTransaction((tx) async {
      final trip = TripPost.fromFirestore(await tx.get(ref));

      validateLifecycle(trip, actor, start ? LifecycleAction.requestStart : LifecycleAction.requestEnd);
      if (uid != actor) throw StateError('Your session changed.');
      tx.set(anchor, {'requestedBy': actor, 'createdAt': FieldValue.serverTimestamp()});
    });
    await _db.runTransaction((tx) async {
      final trip = TripPost.fromFirestore(await tx.get(ref));
      final data = (await tx.get(anchor)).data()!;
      validateLifecycle(trip, actor, start ? LifecycleAction.requestStart : LifecycleAction.requestEnd);
      if (uid != actor) throw StateError('Your session changed.');
      final at = data['createdAt'] as Timestamp;
      tx.update(ref, {
        'status': start ? 'start_requested' : 'end_requested',
        (start ? 'startRequestedAt' : 'endRequestedAt'): at,
        (start ? 'startAutoStartAt' : 'endAutoCompleteAt'): Timestamp(at.seconds + (start ? 180 : 1800), at.nanoseconds),
        (start ? 'startedAt' : 'endedAt'): null,
        (start ? 'startMethod' : 'completionMethod'): null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _transition(String id, LifecycleAction action) async {
    final actor = uid;
    final ref = _db.collection('trip_posts').doc(id);
    await _db.runTransaction((tx) async {
      final trip = TripPost.fromFirestore(await tx.get(ref));
      if (actor != trip.creatorId && actor != trip.acceptedDriverId) throw StateError('Not a trip participant.');
      validateLifecycle(trip, actor, action);
      final completion = action == LifecycleAction.confirmEnd;
      final reputations = <String, UserReputation>{};
      if (completion) {
        for (final party in [trip.creatorId, trip.acceptedDriverId!]) {
          final doc = await tx.get(_db.collection('user_reputation').doc(party));
          reputations[party] = UserReputation.fromMap(doc.data() ?? {}).completed();
        }
      }
      if (uid != actor) throw StateError('Your session changed.');
      tx.update(ref, {
        'status': completion ? 'completed' : 'in_progress',
        (completion ? 'endedAt' : 'startedAt'): FieldValue.serverTimestamp(),
        (completion ? 'completionMethod' : 'startMethod'): 'creator_confirmed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      for (final entry in reputations.entries) {
        tx.set(_db.collection('user_reputation').doc(entry.key), entry.value.toMap());
        tx.update(_db.collection('users').doc(entry.key), {
          'completedTripsCount': FieldValue.increment(1), 'lastCompletedTripId': id,
        });
      }
    });
  }
}
