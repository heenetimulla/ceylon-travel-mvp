import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/trip_post.dart';

TripPost example({
  int adults = 1,
  int kids = 0,
  int bags = 0,
  String creatorType = 'tourist',
  DateTime? scheduledAt,
}) => TripPost(
  id: 'trip-1',
  creatorId: 'user-1',
  creatorType: creatorType,
  creatorName: 'Test Name',
  postType: 'trip_request',
  postOrigin: creatorType == 'tourist' ? 'direct' : 'partner',
  touristId: creatorType == 'tourist' ? 'user-1' : null,
  driverId: creatorType == 'driver' ? 'user-1' : null,
  pickupLocationText: 'Airport',
  dropLocationText: 'Ella',
  scheduledAt: scheduledAt ?? DateTime(2026, 5, 20, 8, 30),
  adultsCount: adults,
  kidsCount: kids,
  baggageCount: bags,
  vehiclePreference: 'Any',
  notes: '',
  status: 'open',
);

void main() {
  test('Cancellation fields initialize and legacy Stage 8 maps default safely', () {
    final map = example().toFirestore();
    expect(map['excludedDriverIds'], isEmpty);
    expect(map['cancellationCount'], 0);
    for (final field in ['lastCancellationBy', 'lastCancellationReason', 'lastCancellationAt']) {
      expect(map[field], isNull);
    }
    for (final field in ['excludedDriverIds', 'cancellationCount',
      'lastCancellationBy', 'lastCancellationReason', 'lastCancellationAt']) {
      map.remove(field);
    }
    final old = TripPost.fromMap('old-trip', map);
    expect(old.excludedDriverIds, isEmpty);
    expect(old.cancellationCount, 0);
    expect(old.lastCancellationBy, isNull);
    expect(old.lastCancellationReason, isNull);
    expect(old.lastCancellationAt, isNull);
    final date = DateTime.utc(2026, 9, 9);
    map.addAll({
      'excludedDriverIds': ['driver-1', 'driver-2'], 'cancellationCount': 2,
      'lastCancellationBy': 'driver-2', 'lastCancellationReason': 'Vehicle issue',
      'lastCancellationAt': Timestamp.fromDate(date),
    });
    final restored = TripPost.fromMap('trip-1', map);
    expect(restored.excludedDriverIds, ['driver-1', 'driver-2']);
    expect(restored.cancellationCount, 2);
    expect(restored.lastCancellationBy, 'driver-2');
    expect(restored.lastCancellationReason, 'Vehicle issue');
    expect(restored.lastCancellationAt!.isAtSameMomentAs(date), isTrue);
    expect(restored.toFirestore()['lastCancellationAt'], Timestamp.fromDate(date));
  });

  test('Post origin distinguishes direct and partner trip requests', () {
    for (final entry in {'tourist': 'direct', 'driver': 'partner'}.entries) {
      final post = example(creatorType: entry.key);
      expect(post.postOrigin, entry.value);
      expect(post.postType, 'trip_request');
      final map = post.toFirestore();
      expect(map['postOrigin'], entry.value);
      expect(map['postType'], 'trip_request');
      final restored = TripPost.fromMap(post.id, map);
      expect(restored.postOrigin, entry.value);
      expect(restored.postType, 'trip_request');
      map.remove('postOrigin');
      expect(TripPost.fromMap(post.id, map).postOrigin, entry.value);
    }
  });

  test('Location, counts and creator getters remain compatible', () {
    final post = example(adults: 2, kids: 1, bags: 3);
    expect(post.pickup, 'Airport');
    expect(post.drop, 'Ella');
    expect(post.adults, 2);
    expect(post.kids, 1);
    expect(post.passengers, '2 adults, 1 kid');
    expect(post.baggage, '3 bags');
    expect(post.creatorTypeLabel, 'Tourist/User');
    expect(post.postedByLabel, 'Posted by Tourist/User');
    expect(example(creatorType: 'driver').postedByLabel, 'Posted by Driver');
  });

  test('Count labels handle singular, plural and zero', () {
    expect(example().passengers, '1 adult');
    expect(example().baggage, '0 bags');
    expect(example(kids: 2, bags: 1).passengers, '1 adult, 2 kids');
    expect(example(bags: 1).baggage, '1 bag');
  });

  test('Date display handles morning, midnight, noon and afternoon', () {
    expect(example().dateTime, '20 May 2026 - 8:30 AM');
    expect(
      example(scheduledAt: DateTime(2026, 1, 1)).dateTime,
      '1 Jan 2026 - 12:00 AM',
    );
    expect(
      example(scheduledAt: DateTime(2026, 1, 1, 12)).dateTime,
      '1 Jan 2026 - 12:00 PM',
    );
    expect(
      example(scheduledAt: DateTime(2026, 12, 31, 23, 5)).dateTime,
      '31 Dec 2026 - 11:05 PM',
    );
  });

  test('Firestore map stores structured values and round trips timestamps', () {
    final post = example();
    final map = post.toFirestore();
    expect(map.keys.toSet(), {
      'id',
      'creatorId',
      'creatorType',
      'creatorName',
      'postType',
      'postOrigin',
      'touristId',
      'driverId',
      'pickupLocationText',
      'dropLocationText',
      'scheduledAt',
      'adultsCount',
      'kidsCount',
      'baggageCount',
      'vehiclePreference',
      'notes',
      'status',
      'acceptedBidId',
      'acceptedDriverId',
      'excludedDriverIds',
      'cancellationCount',
      'lastCancellationBy',
      'lastCancellationReason',
      'lastCancellationAt',
      'tripReference', 'startRequestedAt', 'startAutoStartAt', 'startedAt', 'startMethod',
      'endRequestedAt', 'endAutoCompleteAt', 'endedAt', 'completionMethod',
      'createdAt',
      'updatedAt',
    });
    for (final displayField in [
      'pickup',
      'drop',
      'dateTime',
      'passengers',
      'baggage',
    ]) {
      expect(map.containsKey(displayField), isFalse);
    }
    expect(map['scheduledAt'], isA<Timestamp>());
    final restored = TripPost.fromMap('document-id', map);
    expect(restored.id, 'document-id');
    expect(restored.scheduledAt, post.scheduledAt);
    expect(restored.dateTime, post.dateTime);
    expect(restored.createdAt, isNull);
    expect(restored.updatedAt, isNull);
    expect(restored.acceptedBidId, isNull);
    expect(restored.acceptedDriverId, isNull);

    final now = DateTime(2026, 5, 1);
    map['createdAt'] = Timestamp.fromDate(now);
    map['updatedAt'] = Timestamp.fromDate(now);
    map['scheduledAt'] = post.scheduledAt;
    final dated = TripPost.fromMap('trip-1', map);
    expect(dated.createdAt, now);
    expect(dated.updatedAt, now);
    expect(dated.scheduledAt, post.scheduledAt);
  });

  test('Missing or invalid schedules fail without inventing a date', () {
    for (final invalid in [null, 'tomorrow', 123]) {
      final map = example().toFirestore()..['scheduledAt'] = invalid;
      expect(() => TripPost.fromMap('trip-1', map), throwsFormatException);
    }
  });
}
