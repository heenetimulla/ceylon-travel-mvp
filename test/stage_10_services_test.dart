import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/trip_lifecycle_service.dart';
import 'package:taxi_app/core/services/rating_service.dart';
import 'package:taxi_app/core/services/support_service.dart';
import 'package:taxi_app/core/services/trip_cancellation_service.dart';
import 'package:taxi_app/core/services/trip_chat_service.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'accepted_driver_trips_widget_test.dart' show acceptedTrip;

// In-memory SDK transactions only. These do not execute Firestore security rules.
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
  _Store store() {
    final db = _Store();
    db.docs['trip_posts/trip-1'] = acceptedTrip().toFirestore()..['tripReference'] = 'CT-260910-ABC234';
    for (final uid in ['creator-1', 'driver-1']) {
      db.docs['users/$uid'] = {'status':'active','accountType':'driver','fullName':uid,'phoneNumber':'+94771234567',
        'completedTripsCount':0,'ratingsCount':0,'averageRating':0.0,'ratingStarsTotal':0};
    }
    return db;
  }
  TripLifecycleService lifecycle(_Store db, String uid) => TripLifecycleService(firebaseAuth: _Auth(uid), firestore: db);
  test('Start/end lifecycle uses server anchors, permissions and exact deadlines', () async {
    final db = store();
    await expectLater(lifecycle(db,'driver-1').requestEnd('trip-1'), throwsStateError);
    await expectLater(lifecycle(db,'creator-1').requestStart('trip-1'), throwsStateError);
    await expectLater(lifecycle(db,'stranger').requestStart('trip-1'), throwsStateError);
    await lifecycle(db,'driver-1').requestStart('trip-1');
    var t = db.docs['trip_posts/trip-1']!;
    expect(t['status'],'start_requested');
    expect((t['startAutoStartAt'] as Timestamp).toDate().difference((t['startRequestedAt'] as Timestamp).toDate()), const Duration(minutes:3));
    expect(db.docs['users/driver-1']!['completedTripsCount'],0);
    await expectLater(lifecycle(db,'driver-1').confirmStart('trip-1'), throwsStateError);
    await expectLater(lifecycle(db,'stranger').confirmStart('trip-1'), throwsStateError);
    await lifecycle(db,'creator-1').confirmStart('trip-1');
    expect(t['status'],'in_progress'); expect(t['startMethod'],'creator_confirmed');
    await expectLater(lifecycle(db,'creator-1').requestEnd('trip-1'), throwsStateError);
    await lifecycle(db,'driver-1').requestEnd('trip-1');
    expect((t['endAutoCompleteAt'] as Timestamp).toDate().difference((t['endRequestedAt'] as Timestamp).toDate()), const Duration(minutes:30));
    await expectLater(lifecycle(db,'driver-1').confirmEnd('trip-1'), throwsStateError);
    await lifecycle(db,'creator-1').confirmEnd('trip-1');
    expect(t['status'],'completed'); expect(t['completionMethod'],'creator_confirmed');
    for (final uid in ['creator-1','driver-1']) {
      expect(db.docs['users/$uid']!['completedTripsCount'],1);
      expect(db.docs['user_reputation/$uid']!['completedTripsCount'],1);
    }
    final writes = db.writes.length;
    await expectLater(lifecycle(db,'creator-1').confirmEnd('trip-1'), throwsStateError);
    expect(db.writes.length,writes);
    expect(t['tripReference'],'CT-260910-ABC234');
  });
  // Automatic deadline/retry coverage now lives in functions/test/lifecycle.test.ts.
  test('Progressed lifecycle rejects both Stage 9 cancellation entry points', () async {
    for (final status in ['start_requested','in_progress','end_requested','completed']) {
      final db = store(); db.docs['trip_posts/trip-1']!['status'] = status;
      for (final uid in ['creator-1','driver-1']) {
        final service = TripCancellationService(firebaseAuth:_Auth(uid),firestore:db);
        await expectLater(uid == 'creator-1'
          ? service.cancelByCreator(tripId:'trip-1',reasonCode:'other',reasonText:'Problem')
          : service.cancelByAcceptedDriver(tripId:'trip-1',reasonCode:'other',reasonText:'Problem'), throwsA(isA<TripCancellationException>()));
      }
      expect(db.writes,isEmpty);
    }
  });
  test('Both rating directions aggregate once, reject duplicates and pre-completion', () async {
    final db = store();
    final creator = RatingService(firebaseAuth:_Auth('creator-1'),firestore:db);
    final driver = RatingService(firebaseAuth:_Auth('driver-1'),firestore:db);
    await expectLater(creator.submit(tripId:'trip-1',stars:5,comment:'Good'),throwsStateError);
    db.docs['trip_posts/trip-1']!['status'] = 'completed';
    await creator.submit(tripId:'trip-1',stars:5,comment:'  Good driver  ');
    await driver.submit(tripId:'trip-1',stars:4,comment:'Good creator');
    expect(db.docs['trip_posts/trip-1/ratings/creator_to_driver']!['comment'],'Good driver');
    expect(db.docs['users/driver-1']!['ratingsCount'],1);
    expect(db.docs['users/driver-1']!['averageRating'],5);
    expect(db.docs['users/creator-1']!['ratingsCount'],1);
    expect(db.docs['users/creator-1']!['averageRating'],4);
    final writes = db.writes.length;
    await expectLater(creator.submit(tripId:'trip-1',stars:1,comment:'Again'),throwsStateError);
    expect(db.writes.length,writes);
    expect(db.docs['users/driver-1']!['ratingsCount'],1);
  });
  test('Trip chat creates exact private messages and retries without duplicate writes', () async {
    final db = store();
    final creator = TripChatService(firebaseAuth: _Auth('creator-1'), firestore: db);
    final driver = TripChatService(firebaseAuth: _Auth('driver-1'), firestore: db);
    await creator.sendText(tripId: 'trip-1', messageId: 'text', text: '  Hello  ');
    final text = db.docs['trip_posts/trip-1/messages/text']!;
    expect(text.keys, unorderedEquals(['id', 'tripId', 'senderId', 'senderRole', 'assignmentDriverId', 'messageType', 'text', 'latitude', 'longitude', 'createdAt']));
    expect(text['assignmentDriverId'], 'driver-1');
    expect(text['text'], 'Hello'); expect(text['senderRole'], 'creator');
    expect(text['latitude'], isNull); expect(text['longitude'], isNull);
    expect(text['createdAt'], Timestamp.fromDate(db.now));
    await driver.sendLocation(tripId: 'trip-1', messageId: 'location', latitude: -90, longitude: 180);
    final location = db.docs['trip_posts/trip-1/messages/location']!;
    expect(location['senderRole'], 'driver'); expect(location['text'], isNull);
    expect(location['assignmentDriverId'], 'driver-1');
    expect(location['latitude'], -90); expect(location['longitude'], 180);
    final writes = db.writes.length;
    await creator.sendText(tripId: 'trip-1', messageId: 'text', text: 'Hello');
    await driver.sendLocation(tripId: 'trip-1', messageId: 'location', latitude: -90, longitude: 180);
    expect(db.writes.length, writes);
    await expectLater(creator.sendText(tripId: 'trip-1', messageId: 'text', text: 'Changed'), throwsStateError);
    expect(db.writes.every((path) => path.startsWith('trip_posts/trip-1/messages/')), isTrue);
    expect(db.docs['trip_posts/trip-1']!.containsKey('latitude'), isFalse);
  });
  test('Chat query filters drivers at Firestore and keeps creator history across assignments', () {
    final db = store();
    for (final driverId in ['driver-1', 'driver-2']) {
      db.docs['trip_posts/trip-1']!['acceptedDriverId'] = driverId;
      final trip = TripPost.fromMap('trip-1', db.docs['trip_posts/trip-1']!);
      final driver = TripChatService(firebaseAuth: _Auth(driverId), firestore: db);
      final creator = TripChatService(firebaseAuth: _Auth('creator-1'), firestore: db);
      expect(driver.messagesQuery(trip).parameters['where'], [
        [FieldPath.fromString('assignmentDriverId'), '==', driverId],
      ]);
      expect(creator.messagesQuery(trip).parameters['where'], isEmpty);
      for (final service in [creator, driver]) {
        expect(service.messagesQuery(trip).parameters['orderBy'], [
          [FieldPath.fromString('createdAt'), false],
        ]);
      }
    }
  });
  test('Reacceptance binds new sends to driver B and cannot reuse driver A assignment messages', () async {
    final db = store();
    final creator = TripChatService(firebaseAuth: _Auth('creator-1'), firestore: db);
    await creator.sendText(tripId: 'trip-1', messageId: 'old', text: 'Hello');
    final trip = db.docs['trip_posts/trip-1']!;
    trip['status'] = 'open'; trip['acceptedDriverId'] = null; trip['acceptedBidId'] = null;
    await expectLater(creator.sendText(tripId: 'trip-1', messageId: 'open', text: 'Hello'), throwsStateError);
    trip['status'] = 'accepted'; trip['acceptedDriverId'] = 'driver-2'; trip['acceptedBidId'] = 'bid-2';
    await expectLater(creator.sendText(tripId: 'trip-1', messageId: 'old', text: 'Hello'), throwsStateError);
    await expectLater(creator.sendText(tripId: 'trip-1', messageId: 'stale', text: 'Hello',
      expectedAcceptedDriverId: 'driver-1'), throwsStateError);
    await creator.sendText(tripId: 'trip-1', messageId: 'new', text: 'Hello');
    final driverB = TripChatService(firebaseAuth: _Auth('driver-2'), firestore: db);
    await driverB.sendLocation(tripId: 'trip-1', messageId: 'new-location', latitude: 1, longitude: 2);
    expect(db.docs['trip_posts/trip-1/messages/old']!['assignmentDriverId'], 'driver-1');
    for (final id in ['new', 'new-location']) {
      expect(db.docs['trip_posts/trip-1/messages/$id']!['assignmentDriverId'], 'driver-2');
    }
    expect(db.docs.containsKey('trip_posts/trip-1/messages/stale'), isFalse);
    expect(db.docs.containsKey('trip_posts/trip-1/messages/open'), isFalse);
  });
  test('Trip chat service rejects invalid states, outsiders, changed assignment and invalid payloads', () async {
    final db = store();
    final creator = TripChatService(firebaseAuth: _Auth('creator-1'), firestore: db);
    final outsider = TripChatService(firebaseAuth: _Auth('losing-bidder'), firestore: db);
    await expectLater(outsider.sendText(tripId: 'trip-1', messageId: 'outsider', text: 'Hello'), throwsStateError);
    await expectLater(creator.sendText(tripId: 'trip-1', messageId: 'changed', text: 'Hello', expectedAcceptedDriverId: 'other-driver'), throwsStateError);
    expect(() => creator.sendText(tripId: 'trip-1', messageId: 'empty', text: '  '), throwsArgumentError);
    expect(() => creator.sendLocation(tripId: 'trip-1', messageId: 'invalid', latitude: 91, longitude: 0), throwsArgumentError);
    for (final status in ['open', 'completed', 'cancelled']) {
      db.docs['trip_posts/trip-1']!['status'] = status;
      await expectLater(creator.sendText(tripId: 'trip-1', messageId: status, text: 'Hello'), throwsStateError);
      await expectLater(creator.sendLocation(tripId: 'trip-1', messageId: '${status}_location', latitude: 0, longitude: 0), throwsStateError);
    }
    expect(db.writes, isEmpty);
  });
  test('Creator and driver complaints attach participants/reference; edited phone is immutable snapshot', () async {
    final db = store(); db.docs['trip_posts/trip-1']!['status']='completed';
    for (final uid in ['creator-1','driver-1']) {
      final service = SupportService(firebaseAuth:_Auth(uid),firestore:db);
      final id = await service.create(category:'complaint', contactNumber:'+94779876543', subject:'Trip issue', message:'Please review',
        tripId:'trip-1',subCategory:uid=='creator-1'?'driver_no_show':'payment_incomplete');
      final request = db.docs['support_requests/$id']!;
      expect(request['creatorId'],'creator-1'); expect(request['acceptedDriverId'],'driver-1');
      expect(request['tripReference'],'CT-260910-ABC234'); expect(request['userId'],uid);
      expect(request['supportReference'],startsWith('SUP-')); expect(request['contactNumber'],'+94779876543');
      db.docs['users/$uid']!['phoneNumber']='+94112345678';
      expect(request['contactNumber'],'+94779876543');
      await service.reply(id,'Reply');
      final message = db.docs.entries.singleWhere((e) => e.key.startsWith('support_requests/$id/messages/')).value;
      expect(message['senderRole'],'user'); expect(message['senderId'],uid);
      expect(request['lastMessageId'],message['id']);
      await expectLater(SupportService(firebaseAuth:_Auth('stranger'),firestore:db).reply(id,'Not mine'),throwsStateError);
    }
    expect(db.docs['users/driver-1']!['averageRating'],0);
    expect(db.docs['users/driver-1']!['completedTripsCount'],0);
  });
  test('General support accepts an optional manual complaint reference and requires phone', () async {
    final db=store(); final service=SupportService(firebaseAuth:_Auth('creator-1'),firestore:db);
    await expectLater(service.create(category:'complaint',contactNumber:'',subject:'Issue',message:'Details'),throwsArgumentError);
    final id=await service.create(category:'complaint',contactNumber:'+94771234567',subject:'Issue',message:'Details',manualTripReference:' ct-260910-abc234 ');
    final request=db.docs['support_requests/$id']!;
    expect(request['tripId'],isNull); expect(request['tripReference'],'CT-260910-ABC234');
    expect(request['creatorId'],isNull); expect(request['acceptedDriverId'],isNull);
    request['status']='closed'; await expectLater(service.reply(id,'Again'),throwsStateError);
  });
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
  DateTime now = DateTime.utc(2030, 1, 1, 12);
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
      store.docs[ref.path]!.addAll({for (final entry in data.entries)
        entry.key as String: entry.value is FieldValue
          ? entry.key == 'completedTripsCount' ? (store.docs[ref.path]?['completedTripsCount'] ?? 0) + 1 : Timestamp.fromDate(store.now)
          : entry.value});
    });
    return this;
  }
  @override
  Transaction set<T>(DocumentReference<T> ref, T data, [SetOptions? options]) {
    commits.add(() {
      store.writes.add(ref.path);
      store.docs[ref.path] = {for (final entry in (data as Map).entries)
        entry.key as String: entry.value is FieldValue ? Timestamp.fromDate(store.now) : entry.value};
    });
    return this;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
