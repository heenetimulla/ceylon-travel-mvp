import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/trip_cancellation_service.dart';

import 'accepted_driver_trips_widget_test.dart' show acceptedTrip, acceptedBid;

// In-memory transactions compose real SDK references and snapshots with mocked
// host-channel reads. No native Firebase backend or emulator is used.
// Security rules still require manual verification.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = 'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.initializeCore';
    messenger.setMockMessageHandler(channel, (_) async {
      return const _HostReplyCodec().encodeMessage([
        [
          _HostValue(130, [
            '[DEFAULT]',
            _HostValue(129, [
              'test-api-key', 'test-app-id', 'test-sender', 'test-project',
              ...List<Object?>.filled(10, null),
            ]),
            false,
            <String, Object?>{},
          ]),
        ],
      ]);
    });
    try {
      await Firebase.initializeApp();
    } finally {
      messenger.setMockMessageHandler(channel, null);
    }
  });

  for (final withBids in [false, true]) {
    for (final partner in [false, true]) {
      test('Open withdrawal: bids=$withBids, partner=$partner', () async {
        final store = _Store();
        final parent = acceptedTrip().toFirestore()
          ..['creatorType'] = partner ? 'driver' : 'tourist'
          ..['postOrigin'] = partner ? 'partner' : 'direct'
          ..['touristId'] = partner ? null : 'creator-1'
          ..['driverId'] = partner ? 'creator-1' : null
          ..['status'] = 'open'
          ..['acceptedBidId'] = null
          ..['acceptedDriverId'] = null
          ..['scheduledAt'] = Timestamp.fromDate(DateTime.utc(2020))
          ..['cancellationCount'] = 2
          ..['excludedDriverIds'] = ['previous-driver'];
        store.docs['trip_posts/trip-1'] = parent;
        store.docs['users/creator-1'] = {
          'status': 'active', 'accountType': partner ? 'driver' : 'tourist',
        };
        final submitted = acceptedBid.copyWith(status: 'submitted').toFirestore();
        if (withBids) {
          store.docs['trip_posts/trip-1/bids/driver-1'] = Map.of(submitted);
        }
        await TripCancellationService(firebaseAuth: _Auth('creator-1'), firestore: store)
            .cancelByCreator(tripId: 'trip-1', reasonCode: 'plans_changed', reasonText: '  details  ');
        final after = store.docs['trip_posts/trip-1']!;
        expect(after['status'], 'cancelled');
        expect(after['acceptedBidId'], isNull);
        expect(after['acceptedDriverId'], isNull);
        expect(after['cancellationCount'], 2);
        expect(after['excludedDriverIds'], ['previous-driver']);
        expect(after['lastCancellationReason'], 'Plans changed: details');
        expect(after['lastCancellationBy'], 'creator-1');
        final history = store.docs['trip_posts/trip-1/cancellations/creator-1']!;
        expect(history['id'], 'creator-1');
        expect(history['previousStatus'], 'open');
        expect(history['resultingStatus'], 'cancelled');
        expect(history['cancelledByRole'], 'creator');
        expect(history['penaltyApplied'], isFalse);
        expect(history['cancelledAt'], isA<FieldValue>());
        expect(store.reads, ['users/creator-1', 'trip_posts/trip-1']);
        expect(store.writes, ['trip_posts/trip-1', 'trip_posts/trip-1/cancellations/creator-1']);
        if (withBids) {
          expect(store.docs['trip_posts/trip-1/bids/driver-1'], submitted);
        }
      });
    }
  }

  test('Legacy open withdrawal leaves absent count and exclusions absent', () async {
    final store = _Store();
    store.docs['users/creator-1'] = {'status': 'active', 'accountType': 'tourist'};
    store.docs['trip_posts/trip-1'] = acceptedTrip().toFirestore()
      ..['status'] = 'open'
      ..['acceptedBidId'] = null
      ..['acceptedDriverId'] = null
      ..remove('cancellationCount')
      ..remove('excludedDriverIds');
    await TripCancellationService(firebaseAuth: _Auth('creator-1'), firestore: store)
        .cancelByCreator(tripId: 'trip-1', reasonCode: 'plans_changed', reasonText: '');
    expect(store.docs['trip_posts/trip-1']!.containsKey('cancellationCount'), isFalse);
    expect(store.docs['trip_posts/trip-1']!.containsKey('excludedDriverIds'), isFalse);
  });

  for (final byDriver in [false, true]) {
    test('Accepted cancellation retains original bid update: driver=$byDriver', () async {
      final uid = byDriver ? 'driver-1' : 'creator-1';
      final store = _Store();
      store.docs['users/$uid'] = {'status': 'active', 'accountType': 'driver'};
      store.docs['trip_posts/trip-1'] = acceptedTrip().toFirestore();
      store.docs['trip_posts/trip-1/bids/driver-1'] = acceptedBid.toFirestore();
      final losingBid = acceptedBid.copyWith(status: 'submitted').toFirestore()
        ..['id'] = 'driver-2'
        ..['driverId'] = 'driver-2';
      store.docs['trip_posts/trip-1/bids/driver-2'] = Map.of(losingBid);
      final service = TripCancellationService(firebaseAuth: _Auth(uid), firestore: store);
      if (byDriver) {
        await service.cancelByAcceptedDriver(tripId: 'trip-1', reasonCode: 'vehicle_issue', reasonText: '');
      } else {
        await service.cancelByCreator(tripId: 'trip-1', reasonCode: 'plans_changed', reasonText: '');
      }
      expect(store.docs['trip_posts/trip-1']!['status'], byDriver ? 'open' : 'cancelled');
      expect(store.docs['trip_posts/trip-1']!['cancellationCount'], 1);
      expect(store.docs['trip_posts/trip-1']!['excludedDriverIds'], byDriver ? ['driver-1'] : []);
      expect(store.docs['trip_posts/trip-1/bids/driver-1']!['status'], byDriver ? 'cancelled' : 'trip_cancelled');
      expect(store.docs['trip_posts/trip-1/cancellations/driver-1']!['previousStatus'], 'accepted');
      expect(store.docs['trip_posts/trip-1/bids/driver-2'], losingBid);
    });
  }

  for (final status in ['cancelled', 'completed', 'open']) {
    test('Reject terminal states or non-owner open withdrawal: $status', () async {
      final store = _Store();
      final uid = status == 'open' ? 'intruder' : 'creator-1';
      store.docs['users/$uid'] = {'status': 'active', 'accountType': 'tourist'};
      store.docs['trip_posts/trip-1'] = acceptedTrip().toFirestore()
        ..['status'] = status
        ..['acceptedBidId'] = null
        ..['acceptedDriverId'] = null;
      await expectLater(
        TripCancellationService(firebaseAuth: _Auth(uid), firestore: store)
            .cancelByCreator(tripId: 'trip-1', reasonCode: 'plans_changed', reasonText: ''),
        throwsA(isA<TripCancellationException>()),
      );
      expect(store.writes, isEmpty);
    });
  }
}

class _Auth implements FirebaseAuth {
  _Auth(String uid) : currentUser = _User(uid);
  @override
  final User currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _User implements User {
  _User(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements FirebaseFirestore {
  final docs = <String, Map<String, dynamic>>{};
  final reads = <String>[];
  final writes = <String>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      FirebaseFirestore.instance.collection(path);
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30), int maxAttempts = 5,
  }) async {
    final tx = _Transaction(this);
    final result = await transactionHandler(tx);
    for (final commit in tx.commits) { commit(); }
    return result;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Reply-only wire fixtures for the installed Firebase Core/Firestore Pigeon
// protocols. These are owned values, not subclasses of sealed SDK types.
// The SDK decodes them into its own genuine DocumentSnapshot implementation.
class _HostValue {
  const _HostValue(this.tag, this.fields);
  final int tag;
  final List<Object?> fields;
}

class _HostReplyCodec extends StandardMessageCodec {
  const _HostReplyCodec();

  @override
  void writeValue(WriteBuffer buffer, dynamic value) {
    if (value is _HostValue) {
      buffer.putUint8(value.tag);
      writeValue(buffer, value.fields);
    } else if (value is Timestamp) {
      // Firestore's timestamp tag preserves seconds and nanoseconds exactly.
      buffer.putUint8(188);
      buffer.putInt64(value.seconds);
      buffer.putInt32(value.nanoseconds);
    } else {
      super.writeValue(buffer, value);
    }
  }
}

class _Transaction implements Transaction {
  _Transaction(this.store);
  final _Store store;
  final commits = <void Function()>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> ref) async {
    store.reads.add(ref.path);
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet';
    messenger.setMockMessageHandler(channel, (_) async {
      return const _HostReplyCodec().encodeMessage([
        _HostValue(141, [
          ref.path,
          store.docs[ref.path],
          const _HostValue(140, [false, false]),
        ]),
      ]);
    });
    try {
      return await ref.get();
    } finally {
      messenger.setMockMessageHandler(channel, null);
    }
  }
  @override
  Transaction update(DocumentReference ref, Map<Object, Object?> data) {
    commits.add(() {
      store.writes.add(ref.path);
      store.docs[ref.path]!.addAll(Map<String, dynamic>.from(data));
    });
    return this;
  }
  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    commits.add(() {
      store.writes.add(ref.path);
      store.docs[ref.path] = Map<String, dynamic>.from(data as Map);
    });
    return this;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
