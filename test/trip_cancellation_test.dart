import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/trip_cancellation.dart';

void main() {
  test('Penalty starts strictly below two hours, including past schedules', () {
    final now = DateTime.utc(2026, 9, 9, 10);
    expect(cancellationPenaltyApplies(now.add(const Duration(hours: 3)), now), isFalse);
    expect(cancellationPenaltyApplies(now.add(const Duration(hours: 2)), now), isFalse);
    expect(cancellationPenaltyApplies(now.add(const Duration(hours: 2))
        .subtract(const Duration(microseconds: 1)), now), isTrue);
    expect(cancellationPenaltyApplies(now, now), isTrue);
    expect(cancellationPenaltyApplies(now.subtract(const Duration(hours: 1)), now), isTrue);
  });

  test('A role-specific reason is required and Other requires trimmed details', () {
    for (final reasons in [driverCancellationReasons, creatorCancellationReasons]) {
      expect(validateCancellationReason(null, '', reasons), isNotNull);
      expect(validateCancellationReason('unknown', 'details', reasons), isNotNull);
      expect(validateCancellationReason('other', ' \n ', reasons), isNotNull);
      expect(validateCancellationReason('other', ' explanation ', reasons), isNull);
      expect(validateCancellationReason(reasons.keys.first, '', reasons), isNull);
      expect(validateCancellationReason('other', 'x' * 500, reasons), isNull);
      expect(validateCancellationReason('other', 'x' * 501, reasons), isNotNull);
    }
    expect(validateCancellationReason('vehicle_issue', '', creatorCancellationReasons), isNotNull);
    expect(validateCancellationReason('plans_changed', '', driverCancellationReasons), isNotNull);
  });

  test('Exact history schema, trimmed text, flags and timestamps round trip', () {
    for (final driver in [true, false]) {
      for (final penalty in [true, false]) {
        final record = TripCancellation(id: 'driver-1', tripId: 'trip-1',
          cancelledByUid: driver ? 'driver-1' : 'creator-1',
          cancelledByRole: driver ? 'driver' : 'creator', reasonCode: 'other',
          reasonText: ' details ', penaltyApplied: penalty,
          previousStatus: 'accepted', resultingStatus: driver ? 'open' : 'cancelled');
        final map = record.toFirestore();
        expect(map.keys.toSet(), {'id', 'tripId', 'cancelledByUid',
          'cancelledByRole', 'reasonCode', 'reasonText', 'penaltyApplied',
          'previousStatus', 'resultingStatus', 'cancelledAt'});
        expect(map['reasonText'], 'details');
        expect(TripCancellation.fromMap(record.id, map).cancelledAt, isNull);
        final date = DateTime.utc(2026, 9, 9);
        map['cancelledAt'] = Timestamp.fromDate(date);
        final restored = TripCancellation.fromMap(record.id, map);
        expect(restored.toFirestore(), map);
        expect(restored.penaltyApplied, penalty);
        expect(restored.cancelledAt!.isAtSameMomentAs(date), isTrue);
        map['cancelledAt'] = date;
        expect(TripCancellation.fromMap('actual-id', map).id, 'actual-id');
        map['cancelledAt'] = 'invalid';
        expect(() => TripCancellation.fromMap(record.id, map), throwsFormatException);
      }
    }
  });
}
