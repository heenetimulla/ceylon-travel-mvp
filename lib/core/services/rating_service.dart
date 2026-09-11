import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/rating.dart';
import '../models/trip_post.dart';
import '../models/user_reputation.dart';

class RatingService {
  RatingService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance, _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  String get uid => _auth.currentUser?.uid ?? (throw StateError('Please sign in.'));
  Stream<Rating?> watchOwnRating(TripPost trip) {
    final direction = Rating.direction(trip, uid);
    return _db.collection('trip_posts').doc(trip.id).collection('ratings').doc(direction).snapshots()
      .map((doc) => doc.exists ? Rating.fromMap(doc.data()!) : null);
  }
  Future<void> submit({required String tripId, required int stars, required String comment}) async {
    Rating.validate(stars, comment);
    final actor = uid;
    final parent = _db.collection('trip_posts').doc(tripId);
    await _db.runTransaction((tx) async {
      final trip = TripPost.fromFirestore(await tx.get(parent));
      final direction = Rating.direction(trip, actor);
      final ratedUid = actor == trip.creatorId ? trip.acceptedDriverId! : trip.creatorId;
      final ref = parent.collection('ratings').doc(direction);
      final existing = await tx.get(ref);
      if (existing.exists) throw StateError('You have already rated this trip.');
      final reputationRef = _db.collection('user_reputation').doc(ratedUid);
      final reputationDoc = await tx.get(reputationRef);
      final reputation = UserReputation.fromMap(reputationDoc.data() ?? {}).rated(stars);
      if (uid != actor) throw StateError('Your session changed.');
      final rating = Rating(id: direction, tripId: tripId, tripReference: trip.tripReference,
        ratedByUid: actor, ratedUserUid: ratedUid,
        ratedByRole: actor == trip.creatorId ? 'creator' : 'driver',
        ratingValue: stars.toDouble(), comment: comment.trim());
      tx.set(ref, {...rating.toFirestore(), 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
      tx.set(reputationRef, reputation.toMap());
      tx.update(_db.collection('users').doc(ratedUid), {
        'averageRating': reputation.averageRating, 'ratingsCount': reputation.ratingsCount,
        'ratingStarsTotal': reputation.ratingStarsTotal,
        'lastRatingTripId': tripId, 'lastRatingDirection': direction,
      });
    });
  }
}
