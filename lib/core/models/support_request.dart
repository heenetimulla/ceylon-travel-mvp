import 'package:cloud_firestore/cloud_firestore.dart';
import '../validation/registration_validation.dart';

const supportCategories = {
  'complaint': 'Complaint', 'feedback': 'Feedback', 'suggestion': 'Suggestion',
  'question': 'Ask a Question', 'registration_help': 'Registration Help',
  'app_usage_help': 'App Usage Help', 'other': 'Other',
};
const creatorComplaintCategories = {
  'driver_no_show': 'Driver did not arrive',
  'driver_started_without_passenger': 'Driver started trip without passenger',
  'wrong_start_time': 'Wrong start time', 'wrong_end_time': 'Wrong end time',
  'driver_ended_incorrectly': 'Driver ended trip incorrectly',
  'driver_behaviour': 'Driver behaviour', 'vehicle_issue': 'Vehicle issue',
  'safety_concern': 'Safety concern', 'payment_price_issue': 'Payment/price issue', 'other': 'Other',
};
const driverComplaintCategories = {
  'passenger_no_show': 'Passenger no-show', 'creator_unreachable': 'Creator/customer unreachable',
  'incorrect_hire_details': 'Incorrect hire details', 'wrong_pickup_drop': 'Incorrect pickup/drop details',
  'payment_incorrect': 'Payment incorrect', 'payment_incomplete': 'Payment incomplete',
  'passenger_creator_behaviour': 'Passenger/creator behaviour',
  'trip_changed_unexpectedly': 'Trip changed unexpectedly', 'other': 'Other',
};
String supportAcknowledgement(String category, String reference) => switch (category) {
  'complaint' => 'We received your complaint. Reference: $reference. Our team will review the details and may contact you.',
  'feedback' => "Thank you for your feedback. We've recorded it and will use it to improve Ceylon Travel.",
  'suggestion' => "Thank you for your suggestion. We've recorded it for review.",
  'question' => 'Your question has been received. Our team will review it and respond.',
  'registration_help' => 'Your registration help request has been received. Our team will review it and assist you.',
  'app_usage_help' => 'Your app usage help request has been received. Our team will review it and assist you.',
  _ => 'Your request has been received. Reference: $reference.',
};
void validateSupport({required String category, required String contactNumber, required String subject, required String message}) {
  if (!supportCategories.containsKey(category)) throw ArgumentError('Choose a category.');
  final phoneError = validateRegistrationPhone(contactNumber);
  if (phoneError != null) throw ArgumentError(phoneError);
  if (subject.trim().isEmpty || subject.trim().length > 160) throw ArgumentError('Enter a subject of 1 to 160 characters.');
  if (message.trim().isEmpty || message.trim().length > 4000) throw ArgumentError('Enter a message of 1 to 4000 characters.');
}

class SupportRequest {
  const SupportRequest({required this.id, required this.supportReference,
    required this.userId, required this.userRole, required this.userName,
    required this.contactNumber, required this.category, this.subCategory,
    this.tripId, this.tripReference, this.creatorId, this.acceptedDriverId,
    required this.subject, required this.message, required this.status,
    this.createdAt, this.updatedAt, this.lastMessageAt});
  final String id, supportReference, userId, userRole, userName, contactNumber;
  final String category, subject, message, status;
  final String? subCategory, tripId, tripReference, creatorId, acceptedDriverId;
  final DateTime? createdAt, updatedAt, lastMessageAt;
  String get acknowledgement => supportAcknowledgement(category, supportReference);
  factory SupportRequest.fromMap(Map<String, dynamic> d) => SupportRequest(
    id: d['id'], supportReference: d['supportReference'], userId: d['userId'],
    userRole: d['userRole'], userName: d['userName'], contactNumber: d['contactNumber'],
    category: d['category'], subCategory: d['subCategory'], tripId: d['tripId'], tripReference: d['tripReference'],
    creatorId: d['creatorId'], acceptedDriverId: d['acceptedDriverId'],
    subject: d['subject'], message: d['message'], status: d['status'],
    createdAt: (d['createdAt'] as Timestamp?)?.toDate(), updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
  );
  Map<String, dynamic> toFirestore() => {
    'id': id, 'supportReference': supportReference, 'userId': userId,
    'userRole': userRole, 'userName': userName, 'contactNumber': contactNumber,
    'category': category, 'subCategory': subCategory, 'tripId': tripId,
    'tripReference': tripReference, 'creatorId': creatorId, 'acceptedDriverId': acceptedDriverId,
    'subject': subject, 'message': message, 'status': status,
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    'lastMessageAt': lastMessageAt == null ? null : Timestamp.fromDate(lastMessageAt!),
  };
}
