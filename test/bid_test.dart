import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:taxi_app/core/widgets/bid_card.dart';
import 'package:taxi_app/core/models/bid.dart';
import 'package:taxi_app/core/models/trip_post.dart';

Bid example({int price = 18500, int minutes = 90, double cancellation = 10}) =>
    Bid(
      id: 'driver-1',
      tripId: 'trip-1',
      driverId: 'driver-1',
      driverName: 'Test Driver',
      driverRating: 4.5,
      completedTrips: 12,
      cancellationRate: cancellation,
      priceAmount: price,
      vehicleType: 'Small Car',
      vehicleDetails: 'Suzuki Wagon R Stingray 2017, White',
      vehicleNumber: 'WP CAB-1234',
      estimatedTripMinutes: minutes,
      message: 'Happy to help with luggage.',
      status: 'submitted',
    );

void main() {
  test('Price formats integer LKR with grouping', () {
    expect(example().price, 'LKR 18,500');
    expect(example(price: 1).price, 'LKR 1');
    expect(example(price: 10000000).price, 'LKR 10,000,000');
  });

  test('Duration formats minutes, hours and days', () {
    for (final entry in {
      1: '1 minute',
      60: '1 hour',
      90: '1 hour 30 minutes',
      300: '5 hours',
      330: '5 hours 30 minutes',
      1440: '1 day',
      1501: '1 day 1 hour 1 minute',
      10080: '7 days',
    }.entries) {
      expect(example(minutes: entry.key).estimatedTravelTime, entry.value);
    }
  });

  test('Cancellation rate stays numeric with a percentage display getter', () {
    expect(example(cancellation: 0).cancellationRateLabel, '0%');
    expect(example().cancellationRateLabel, '10%');
    expect(example(cancellation: 2.5).cancellationRateLabel, '2.5%');
    expect(example().toFirestore()['cancellationRate'], 10.0);
    expect(example().toFirestore()['cancellationRate'], isA<double>());
  });

  test('Exact schema and vehicle details persist through conversion', () {
    final bid = example();
    final map = bid.toFirestore();
    expect(map.length, 16);
    expect(map.keys.toSet(), {
      'id',
      'tripId',
      'driverId',
      'driverName',
      'driverRating',
      'completedTrips',
      'cancellationRate',
      'priceAmount',
      'vehicleType',
      'vehicleDetails',
      'vehicleNumber',
      'estimatedTripMinutes',
      'message',
      'status',
      'createdAt',
      'updatedAt',
    });
    final restored = Bid.fromMap(bid.id, map);
    expect(restored.toFirestore(), map);
    expect(restored.vehicleDetails, 'Suzuki Wagon R Stingray 2017, White');
    expect(restored.vehicleNumber, 'WP CAB-1234');
    expect(restored.createdAt, isNull);
    expect(restored.updatedAt, isNull);
    map['driverRating'] = 4;
    map['cancellationRate'] = 0;
    final numeric = Bid.fromMap(bid.id, map);
    expect(numeric.driverRating, 4.0);
    expect(numeric.cancellationRate, 0.0);
  });

  test('Timestamps round trip and document ID is authoritative', () {
    final created = DateTime.utc(2026, 9, 8, 10);
    final updated = DateTime.utc(2026, 9, 8, 11);
    final map = example().toFirestore()
      ..['createdAt'] = Timestamp.fromDate(created)
      ..['updatedAt'] = Timestamp.fromDate(updated);
    final restored = Bid.fromMap('actual-driver-id', map);
    expect(restored.id, 'actual-driver-id');
    expect(restored.createdAt!.isAtSameMomentAs(created), isTrue);
    expect(restored.updatedAt!.isAtSameMomentAs(updated), isTrue);
    expect(restored.toFirestore()['createdAt'], Timestamp.fromDate(created));
    expect(restored.toFirestore()['updatedAt'], Timestamp.fromDate(updated));
    map['createdAt'] = 'invalid';
    expect(() => Bid.fromMap('driver-1', map), throwsFormatException);
  });

  test(
    'Effective CLOSED is derived from parent and never mutates losing bids',
    () {
      TripPost trip(String status, String? acceptedId) => TripPost(
        id: 'trip-1',
        creatorId: 'creator-1',
        creatorType: 'driver',
        creatorName: 'Partner',
        postType: 'trip_request',
        postOrigin: 'partner',
        driverId: 'creator-1',
        pickupLocationText: 'Colombo',
        dropLocationText: 'Ella',
        scheduledAt: DateTime.utc(2030),
        adultsCount: 1,
        kidsCount: 0,
        baggageCount: 0,
        vehiclePreference: 'Any',
        notes: '',
        status: status,
        acceptedBidId: acceptedId,
        acceptedDriverId: acceptedId,
      );
      final bid = example();
      expect(bid.effectiveStatusFor(trip('open', null)), 'submitted');
      expect(bid.effectiveStatusFor(trip('accepted', bid.id)), 'accepted');
      expect(
        bid.effectiveStatusFor(trip('accepted', 'other-driver')),
        'closed',
      );
      expect(bid.copyWith(status: 'cancelled').effectiveStatusFor(trip('open', null)), 'cancelled');
      expect(bid.copyWith(status: 'cancelled').effectiveStatusFor(trip('accepted', 'other-driver')), 'cancelled');
      expect(bid.copyWith(status: 'trip_cancelled').effectiveStatusFor(trip('cancelled', null)), 'trip_cancelled');
      expect(bid.effectiveStatusFor(trip('cancelled', null)), 'trip_cancelled');
      expect(bid.status, 'submitted');
      expect(bid.toFirestore()['status'], 'submitted');
      expect(bid.effectiveStatusFor(trip('open', null)), 'submitted');
    },
  );

  testWidgets(
    'Bid card shows actual vehicle and disables effective CLOSED bids',
    (tester) async {
      var accepts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: BidCard(
                bid: example(),
                effectiveStatus: 'closed',
                onAccept: () => accepts++,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Vehicle type: Small Car'), findsOneWidget);
      expect(
        find.text('Vehicle: Suzuki Wagon R Stingray 2017, White'),
        findsOneWidget,
      );
      expect(find.text('Vehicle number: WP CAB-1234'), findsOneWidget);
      expect(find.text('CLOSED'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(accepts, 0);
    },
  );

  test('Legacy bids without a vehicle number remain readable', () {
    final map = example().toFirestore()..remove('vehicleNumber');
    expect(Bid.fromMap('driver-1', map).vehicleNumber, isEmpty);
  });

  test('copyWith status preserves all other fields and original bid', () {
    final map = example().toFirestore()
      ..['createdAt'] = Timestamp.fromDate(DateTime.utc(2026, 9, 8))
      ..['updatedAt'] = Timestamp.fromDate(DateTime.utc(2026, 9, 9));
    final original = Bid.fromMap('driver-1', map);
    final changed = original.copyWith(status: 'accepted');
    expect(changed.toFirestore(), {...map, 'status': 'accepted'});
    expect(original.status, 'submitted');
    expect(changed.vehicleNumber, 'WP CAB-1234');
    expect(original.copyWith().toFirestore(), map);
  });
}
