import 'user_reputation.dart';
import 'trip_post.dart';

class PublicProfile {
  const PublicProfile({required this.uid, required this.fullName, this.profilePhotoPath,
    this.verificationStatus = 'not_verified', this.reputation});
  final String uid, fullName, verificationStatus;
  final String? profilePhotoPath;
  final UserReputation? reputation;
  factory PublicProfile.fromMap(Map<String, dynamic> data) => PublicProfile(
    uid: data['uid'] as String,
    fullName: data['fullName'] as String? ?? '',
    profilePhotoPath: data['profilePhotoPath'] as String?,
    verificationStatus: data['verificationStatus'] as String? ?? 'not_verified',
    reputation: data['completedTripsCount'] == null ? null : UserReputation.fromMap(data),
  );
  Map<String, dynamic> toMap() => {
    'uid': uid, 'fullName': fullName, 'profilePhotoPath': profilePhotoPath,
    'verificationStatus': verificationStatus,
    'completedTripsCount': reputation?.completedTripsCount,
    'cancellationCount': reputation?.cancellationCount,
    'cancellationRate': reputation?.cancellationRate,
    'averageRating': reputation?.averageRating, 'ratingsCount': reputation?.ratingsCount,
  };
  static String? otherParticipant(TripPost trip, String actor) {
    if (!TripPost.assignedStatuses.contains(trip.status) ||
        trip.acceptedDriverId == null || trip.acceptedDriverId!.isEmpty ||
        trip.acceptedDriverId == trip.creatorId) {
      return null;
    }
    if (actor == trip.creatorId) return trip.acceptedDriverId;
    if (actor == trip.acceptedDriverId) return trip.creatorId;
    return null;
  }
}
