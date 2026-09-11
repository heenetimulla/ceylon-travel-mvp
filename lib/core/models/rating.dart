import 'package:cloud_firestore/cloud_firestore.dart';
import 'trip_post.dart';

class Rating {
  const Rating({required this.id, required this.tripId, this.fromUserName = '',
    this.toUserName = '', required this.ratingValue, required this.comment,
    this.createdAtText = '', this.tripReference, this.ratedByUid,
    this.ratedUserUid, this.ratedByRole, this.createdAt, this.updatedAt});
  final String id, tripId, fromUserName, toUserName, comment, createdAtText;
  final double ratingValue;
  final String? tripReference, ratedByUid, ratedUserUid, ratedByRole;
  final DateTime? createdAt, updatedAt;
  int get stars => ratingValue.toInt();
  static String direction(TripPost trip, String uid) {
    if (trip.status != 'completed') throw StateError('Complete this trip before rating.');
    if (trip.acceptedDriverId == null || trip.creatorId == trip.acceptedDriverId) throw StateError('A valid opposite party is required.');
    if (uid == trip.creatorId) return 'creator_to_driver';
    if (uid == trip.acceptedDriverId) return 'driver_to_creator';
    throw StateError('Only trip participants can rate each other.');
  }
  static void validate(int stars, String comment) {
    if (stars < 1 || stars > 5) throw ArgumentError('Choose 1 to 5 stars.');
    if (comment.trim().isEmpty || comment.trim().length > 1000) throw ArgumentError('Write a comment of 1 to 1000 characters.');
  }
  factory Rating.fromMap(Map<String, dynamic> data) => Rating(
    id: data['id'] as String, tripId: data['tripId'] as String,
    tripReference: data['tripReference'] as String?,
    ratedByUid: data['ratedByUid'] as String, ratedUserUid: data['ratedUserUid'] as String,
    ratedByRole: data['ratedByRole'] as String,
    ratingValue: (data['stars'] as num).toDouble(), comment: data['comment'] as String,
    createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
  );
  Map<String, dynamic> toFirestore() => {
    'id': id, 'tripId': tripId, 'tripReference': tripReference,
    'ratedByUid': ratedByUid, 'ratedUserUid': ratedUserUid, 'ratedByRole': ratedByRole,
    'stars': stars, 'comment': comment.trim(),
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
  };
}
