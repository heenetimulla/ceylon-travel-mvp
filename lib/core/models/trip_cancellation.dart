import 'package:cloud_firestore/cloud_firestore.dart';

const driverCancellationReasons = {
  'vehicle_issue': 'Vehicle issue',
  'personal_emergency': 'Personal emergency',
  'scheduling_conflict': 'Scheduling conflict',
  'unable_to_complete_trip': 'Unable to complete trip',
  'other': 'Other',
};
const creatorCancellationReasons = {
  'plans_changed': 'Plans changed',
  'trip_no_longer_required': 'Trip no longer required',
  'date_or_time_changed': 'Date or time changed',
  'found_another_arrangement': 'Found another arrangement',
  'other': 'Other',
};

bool cancellationPenaltyApplies(DateTime scheduledAt, DateTime cancelledAt) =>
    scheduledAt.difference(cancelledAt) < const Duration(hours: 2);

String? validateCancellationReason(
  String? code,
  String text,
  Map<String, String> reasons,
) {
  if (!reasons.containsKey(code)) return 'Select a cancellation reason.';
  if (text.trim().length > 500) return 'Keep details within 500 characters.';
  if (code == 'other' && text.trim().isEmpty) return 'Enter details for Other.';
  return null;
}

class TripCancellation {
  const TripCancellation({
    required this.id,
    required this.tripId,
    required this.cancelledByUid,
    required this.cancelledByRole,
    required this.reasonCode,
    required this.reasonText,
    required this.penaltyApplied,
    required this.previousStatus,
    required this.resultingStatus,
    this.cancelledAt,
  });

  final String id, tripId, cancelledByUid, cancelledByRole;
  final String reasonCode, reasonText, previousStatus, resultingStatus;
  final bool penaltyApplied;
  final DateTime? cancelledAt;

  factory TripCancellation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) {
      throw const FormatException('Cancellation does not exist.');
    }
    return TripCancellation.fromMap(doc.id, data);
  }

  factory TripCancellation.fromMap(String id, Map<String, dynamic> data) {
    final date = data['cancelledAt'];
    if (date != null && date is! Timestamp && date is! DateTime) {
      throw const FormatException('Invalid cancellation timestamp.');
    }
    return TripCancellation(
      id: id,
      tripId: data['tripId'] as String,
      cancelledByUid: data['cancelledByUid'] as String,
      cancelledByRole: data['cancelledByRole'] as String,
      reasonCode: data['reasonCode'] as String,
      reasonText: data['reasonText'] as String,
      penaltyApplied: data['penaltyApplied'] as bool,
      previousStatus: data['previousStatus'] as String,
      resultingStatus: data['resultingStatus'] as String,
      cancelledAt: date is Timestamp ? date.toDate() : date as DateTime?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'tripId': tripId,
    'cancelledByUid': cancelledByUid,
    'cancelledByRole': cancelledByRole,
    'reasonCode': reasonCode,
    'reasonText': reasonText.trim(),
    'penaltyApplied': penaltyApplied,
    'previousStatus': previousStatus,
    'resultingStatus': resultingStatus,
    'cancelledAt': cancelledAt == null
        ? null
        : Timestamp.fromDate(cancelledAt!),
  };
}
