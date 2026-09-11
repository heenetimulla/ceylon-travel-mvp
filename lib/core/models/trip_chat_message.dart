import 'package:cloud_firestore/cloud_firestore.dart';
import 'trip_post.dart';

class TripChatMessage {
  const TripChatMessage({required this.id, required this.tripId, required this.senderId,
    required this.senderRole, required this.assignmentDriverId, required this.messageType, this.text, this.latitude,
    this.longitude, this.createdAt});
  final String id, tripId, senderId, senderRole, assignmentDriverId, messageType;
  final String? text;
  final double? latitude, longitude;
  final DateTime? createdAt;
  static const writableStates = ['accepted', 'start_requested', 'in_progress', 'end_requested'];

  static bool canRead(TripPost trip, String uid) => uid.isNotEmpty &&
    (uid == trip.creatorId || hasCurrentAssignment(trip, uid));

  static bool hasCurrentAssignment(TripPost trip, String uid) => uid.isNotEmpty &&
    trip.acceptedDriverId != null && trip.acceptedDriverId!.isNotEmpty &&
    trip.acceptedDriverId != trip.creatorId &&
    trip.acceptedBidId != null && trip.acceptedBidId!.isNotEmpty &&
    (uid == trip.creatorId || uid == trip.acceptedDriverId) &&
    [...writableStates, 'completed', 'cancelled'].contains(trip.status);
  static bool canWrite(TripPost trip, String uid) => hasCurrentAssignment(trip, uid) && writableStates.contains(trip.status);

  // Driver queries enforce this boundary on the server as well. Assignment ownership
  // is immutable and verified against the parent acceptedDriverId at creation.
  bool isVisibleTo(String creatorId, String uid) => uid.isNotEmpty &&
    (uid == creatorId || (assignmentDriverId.isNotEmpty && assignmentDriverId == uid));

  static String validateText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) {
      throw ArgumentError('Write a message of 1 to 1000 characters.');
    }
    return trimmed;
  }
  static void validateLocation(double latitude, double longitude) {
    if (!latitude.isFinite || !longitude.isFinite || latitude < -90 || latitude > 90 ||
        longitude < -180 || longitude > 180) {
      throw ArgumentError('The location is invalid. Please try again.');
    }
  }
  bool get isValid {
    if (id.isEmpty || tripId.isEmpty || senderId.isEmpty || assignmentDriverId.isEmpty ||
        !['creator', 'driver'].contains(senderRole)) {
      return false;
    }
    try {
      if (messageType == 'text') return text != null && validateText(text!) == text && latitude == null && longitude == null;
      if (messageType == 'location' && text == null && latitude != null && longitude != null) {
        validateLocation(latitude!, longitude!);
        return true;
      }
    } on ArgumentError { return false; }
    return false;
  }
  factory TripChatMessage.fromMap(String id, Map<String, dynamic>? data) {
    final d = data ?? <String, dynamic>{};
    final validTypes = (d['text'] == null || d['text'] is String) &&
      (d['latitude'] == null || d['latitude'] is num) && (d['longitude'] == null || d['longitude'] is num) &&
      (d['createdAt'] == null || d['createdAt'] is Timestamp);
    return TripChatMessage(id: id,
      tripId: d['tripId'] is String ? d['tripId'] as String : '',
      senderId: d['senderId'] is String ? d['senderId'] as String : '',
      senderRole: d['senderRole'] is String ? d['senderRole'] as String : '',
      assignmentDriverId: d['assignmentDriverId'] is String ? d['assignmentDriverId'] as String : '',
      messageType: validTypes && d['id'] == id && d['messageType'] is String ? d['messageType'] as String : 'invalid',
      text: d['text'] is String ? d['text'] as String : null,
      latitude: d['latitude'] is num ? (d['latitude'] as num).toDouble() : null,
      longitude: d['longitude'] is num ? (d['longitude'] as num).toDouble() : null,
      createdAt: d['createdAt'] is Timestamp ? (d['createdAt'] as Timestamp).toDate() : null);
  }
  Map<String, dynamic> toFirestore() => {
    'id': id, 'tripId': tripId, 'senderId': senderId, 'senderRole': senderRole,
    'assignmentDriverId': assignmentDriverId,
    'messageType': messageType, 'text': text, 'latitude': latitude, 'longitude': longitude,
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
  };
}
