import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:taxi_app/core/models/public_profile.dart';
import 'package:taxi_app/core/models/trip_chat_message.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/services/trip_location_service.dart';
import 'package:taxi_app/screens/chat/trip_chat_screen.dart';
import 'accepted_driver_trips_widget_test.dart' show acceptedTrip;

TripPost chatTrip(String status) => TripPost.fromMap('trip-1', acceptedTrip().toFirestore()
  ..['status'] = status ..['tripReference'] = 'CT-260911-ABC234');
TripChatMessage textMessage(String id, String sender, String text, {String assignment = 'driver-1'}) => TripChatMessage(
  id: id, tripId: 'trip-1', senderId: sender, senderRole: sender == 'creator-1' ? 'creator' : 'driver',
  assignmentDriverId: assignment, messageType: 'text', text: text, createdAt: DateTime(2026, 9, 11, 12));
const locationMessage = TripChatMessage(id: 'location', tripId: 'trip-1', senderId: 'driver-1',
  senderRole: 'driver', assignmentDriverId: 'driver-1', messageType: 'location', latitude: 6.9271, longitude: 79.8612);

// Flush stream/future microtasks, then render their state and post-frame scroll.
// Do not wait for loading indicators, focused cursors or pending GPS to settle.
Future<void> pumpChat(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> withTripUpdates(WidgetTester tester,
  Future<void> Function(StreamController<TripPost>, StreamController<List<TripChatMessage>>) body,
  {Completer<TripCoordinates>? coordinates}) async {
  final trips = StreamController<TripPost>.broadcast(sync: true);
  final messages = StreamController<List<TripChatMessage>>.broadcast(sync: true);
  var cleanedUp = false;
  Future<void> cleanup() async {
    if (cleanedUp) {
      return;
    }
    cleanedUp = true;
    // Dispose/cancel listeners first so failure cleanup cannot accidentally send.
    await tester.pumpWidget(const SizedBox());
    if (coordinates != null && !coordinates.isCompleted) {
      coordinates.complete(const TripCoordinates(0, 0));
    }
    final closed = Future.wait([trips.close(), messages.close()]);
    // close() and GPS continuations can enqueue fake-async microtasks. Drain them
    // before awaiting closure rather than leaving the test waiting on that queue.
    await pumpChat(tester);
    await closed;
  }
  addTearDown(cleanup);
  try {
    await body(trips, messages);
  } finally {
    // Run before Flutter's timer/debug invariants, even when an assertion fails.
    await cleanup();
  }
}

Future<void> showChat(WidgetTester tester, {String actor = 'creator-1', String status = 'accepted',
  List<TripChatMessage> messages = const [], Stream<TripPost>? trips,
  Stream<List<TripChatMessage>>? messagesStream,
  Future<void> Function(TripChatMessage)? onSend, TripLocationService? location}) async {
  var id = 0;
  await tester.pumpWidget(MaterialApp(home: TripChatScreen(tripPost: chatTrip(status), actorUid: actor,
    tripStream: trips ?? Stream.value(chatTrip(status)), messagesStream: messagesStream ?? Stream.value(messages),
    // Reassignment replaces the header subscription; replay the fake profile for
    // each listener instead of reusing an exhausted single-subscription stream.
    profileStream: Stream<PublicProfile?>.multi((controller) {
      controller.add(PublicProfile(uid: actor == 'creator-1' ? 'driver-1' : 'creator-1', fullName: 'Other Participant'));
      controller.close();
    }),
    messageIdFactory: () => 'outgoing-${id++}', onSend: onSend ?? (_) async {}, locationService: location)));
  await pumpChat(tester);
}

void main() {
  // Flutter already selects Android under FLUTTER_TEST. Do not override a debug
  // global in setUp: widget-test invariants run before package:test tearDown.
  test('Text and location parsing preserves schema and safely handles pending/invalid data', () {
    final original = textMessage('text', 'creator-1', 'At the entrance');
    final text = TripChatMessage.fromMap('text', original.toFirestore());
    expect(text.isValid, isTrue); expect(text.text, 'At the entrance');
    expect(text.createdAt, original.createdAt); expect(text.latitude, isNull);
    final location = TripChatMessage.fromMap('location', locationMessage.toFirestore());
    expect(location.isValid, isTrue); expect(location.latitude, 6.9271);
    expect(location.text, isNull); expect(location.createdAt, isNull);
    expect(location.toFirestore().keys, unorderedEquals(['id', 'tripId', 'senderId', 'senderRole',
      'assignmentDriverId', 'messageType', 'text', 'latitude', 'longitude', 'createdAt']));
    expect(text.assignmentDriverId, 'driver-1');
    expect(TripChatMessage.fromMap('text', original.toFirestore()..remove('assignmentDriverId')).isValid, isFalse);
    expect(TripChatMessage.fromMap('bad', null).isValid, isFalse);
    for (final patch in [{'text': 42}, {'messageType': 'system'}, {'latitude': 'not a coordinate'},
      {'senderRole': 'admin'}, {'createdAt': 'not a timestamp'}, {'id': 'wrong'},
      {'assignmentDriverId': null}, {'assignmentDriverId': ''}, {'assignmentDriverId': 42}]) {
      expect(TripChatMessage.fromMap('text', {...original.toFirestore(), ...patch}).isValid, isFalse);
    }
    expect(TripChatMessage.fromMap('text', {...original.toFirestore(), 'createdAt': null}).isValid, isTrue);
  });
  test('Text trimming and coordinate finite/range validation', () {
    expect(TripChatMessage.validateText('  Hello \n'), 'Hello');
    for (final value in ['', ' \n ', 'x' * 1001]) {
      expect(() => TripChatMessage.validateText(value), throwsArgumentError);
    }
    expect(TripChatMessage.validateText('x' * 1000).length, 1000);
    for (final pair in [(-90.0, -180.0), (90.0, 180.0), (0.0, 0.0)]) {
      expect(() => TripChatMessage.validateLocation(pair.$1, pair.$2), returnsNormally);
    }
    for (final pair in [(-90.01, 0.0), (90.01, 0.0), (0.0, -180.01), (0.0, 180.01),
      (double.nan, 0.0), (0.0, double.infinity)]) {
      expect(() => TripChatMessage.validateLocation(pair.$1, pair.$2), throwsArgumentError);
    }
  });
  test('Creator retains history; current driver reads assigned chat; non-active states deny writes', () {
    for (final state in TripChatMessage.writableStates) {
      for (final actor in ['creator-1', 'driver-1']) {
        expect(TripChatMessage.canRead(chatTrip(state), actor), isTrue);
        expect(TripChatMessage.canWrite(chatTrip(state), actor), isTrue);
      }
      for (final actor in ['losing-bidder', 'stranger', '']) {
        expect(TripChatMessage.canRead(chatTrip(state), actor), isFalse);
        expect(TripChatMessage.canWrite(chatTrip(state), actor), isFalse);
      }
    }
    for (final state in ['completed', 'cancelled']) {
      expect(TripChatMessage.canRead(chatTrip(state), 'creator-1'), isTrue);
      expect(TripChatMessage.canWrite(chatTrip(state), 'creator-1'), isFalse);
    }
    expect(TripChatMessage.canRead(chatTrip('open'), 'creator-1'), isTrue);
    expect(TripChatMessage.canWrite(chatTrip('open'), 'creator-1'), isFalse);
    final reopened = TripPost.fromMap('trip-1', chatTrip('open').toFirestore()..['acceptedDriverId'] = null);
    expect(TripChatMessage.canRead(reopened, 'driver-1'), isFalse);
    final partner = TripPost.fromMap('trip-1', chatTrip('accepted').toFirestore()..['driverId'] = 'partner-only');
    expect(TripChatMessage.canRead(partner, 'partner-only'), isFalse);
  });
  test('Assignment visibility isolates both drivers and old coordinates while creator retains both', () {
    final a = textMessage('a', 'creator-1', 'For driver A');
    final b = textMessage('b', 'creator-1', 'For driver B', assignment: 'driver-2');
    for (final message in [a, locationMessage]) {
      expect(message.isVisibleTo('creator-1', 'creator-1'), isTrue);
      expect(message.isVisibleTo('creator-1', 'driver-1'), isTrue);
      expect(message.isVisibleTo('creator-1', 'driver-2'), isFalse);
      expect(message.isVisibleTo('creator-1', 'losing-bidder'), isFalse);
    }
    expect(b.isVisibleTo('creator-1', 'creator-1'), isTrue);
    expect(b.isVisibleTo('creator-1', 'driver-2'), isTrue);
    expect(b.isVisibleTo('creator-1', 'driver-1'), isFalse);
  });
  for (final actor in ['creator-1', 'driver-2']) {
    testWidgets('Reaccepted chat isolates old text and GPS for $actor', (tester) async {
      final reassigned = TripPost.fromMap('trip-1', chatTrip('accepted').toFirestore()
        ..['acceptedDriverId'] = 'driver-2' ..['acceptedBidId'] = 'bid-2');
      await showChat(tester, actor: actor, trips: Stream.value(reassigned), messages: [
        textMessage('a', 'creator-1', 'For driver A'), locationMessage,
        textMessage('b', 'creator-1', 'For driver B', assignment: 'driver-2'),
      ]);
      expect(find.text('For driver B'), findsOneWidget);
      expect(find.text('For driver A'), actor == 'creator-1' ? findsOneWidget : findsNothing);
      expect(find.text('Location shared'), actor == 'creator-1' ? findsOneWidget : findsNothing);
      expect(find.text('Open in Maps'), actor == 'creator-1' ? findsOneWidget : findsNothing);
    });
  }
  for (final actor in ['creator-1', 'driver-1']) {
    testWidgets('Participant $actor sees real messages, safe identity and can send trimmed text', (tester) async {
      TripChatMessage? sent;
      await showChat(tester, actor: actor, messages: [textMessage('old', 'driver-1', 'At the entrance'),
        textMessage('new', 'creator-1', 'Coming now')], onSend: (message) async { sent = message; });
      expect(find.text('At the entrance'), findsOneWidget);
      expect(find.text('Coming now'), findsOneWidget);
      expect(tester.getTopLeft(find.text('At the entrance')).dy, lessThan(tester.getTopLeft(find.text('Coming now')).dy));
      expect(find.text('Other Participant'), findsOneWidget); expect(find.text('OP'), findsOneWidget);
      expect(find.text('Trip: CT-260911-ABC234'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('trip_chat_text')), '  On my way  ');
      await tester.tap(find.byKey(const Key('trip_chat_send'))); await pumpChat(tester);
      expect(sent!.text, 'On my way'); expect(sent!.senderId, actor);
      expect(sent!.senderRole, actor == 'creator-1' ? 'creator' : 'driver');
      expect(sent!.latitude, isNull);
      expect(sent!.assignmentDriverId, 'driver-1');
    });
  }
  testWidgets('Completed history renders text/location/maps but no write controls', (tester) async {
    Uri? opened;
    await showChat(tester, status: 'completed', messages: [textMessage('a', 'creator-1', 'Thank you'), locationMessage],
      location: TripLocationService(launch: (uri) async { opened = uri; return true; }));
    expect(find.text('Thank you'), findsOneWidget);
    expect(find.text('Location shared'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(find.text('Chat history is read-only.'), findsOneWidget);
    expect(find.byKey(const Key('trip_chat_text')), findsNothing);
    expect(find.byKey(const Key('trip_chat_share_location')), findsNothing);
    expect(find.byKey(const Key('trip_chat_send')), findsNothing);
    expect(find.textContaining('6.9271'), findsNothing);
    await tester.tap(find.text('Open in Maps')); await pumpChat(tester);
    expect(opened!.scheme, 'https'); expect(opened!.host, 'www.google.com');
    expect(opened!.queryParameters['query'], '6.9271,79.8612');
  });
  testWidgets('Empty state and retry keep one message ID/payload', (tester) async {
    final attempts = <TripChatMessage>[];
    await showChat(tester, onSend: (message) async {
      attempts.add(message); if (attempts.length == 1) throw StateError('uncertain result');
    });
    expect(find.textContaining('No messages yet'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('trip_chat_text')), 'Retry safely');
    await tester.tap(find.byKey(const Key('trip_chat_send'))); await pumpChat(tester);
    expect(find.textContaining('Could not confirm delivery'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trip_chat_retry_send'))); await pumpChat(tester);
    expect(attempts.length, 2); expect(attempts[1].id, attempts[0].id);
    expect(attempts[1].text, attempts[0].text);
  });
  testWidgets('Trip completion and reopen retain creator history without a composer', (tester) async {
    await withTripUpdates(tester, (trips, _) async {
      await tester.pumpWidget(MaterialApp(home: TripChatScreen(tripPost: chatTrip('accepted'), actorUid: 'creator-1',
        tripStream: trips.stream, messagesStream: Stream.value([textMessage('a', 'driver-1', 'Private text')]),
        profileStream: Stream.value(null))));
      trips.add(chatTrip('accepted')); await pumpChat(tester);
      expect(find.text('Private text'), findsOneWidget);
      trips.add(chatTrip('completed')); await pumpChat(tester);
      expect(find.byKey(const Key('trip_chat_text')), findsNothing);
      trips.add(TripPost.fromMap('trip-1', chatTrip('open').toFirestore()
        ..['acceptedDriverId'] = null ..['acceptedBidId'] = null)); await pumpChat(tester);
      expect(find.text('Private text'), findsOneWidget);
      expect(find.text('Chat history is read-only.'), findsOneWidget);
      expect(find.byKey(const Key('trip_chat_text')), findsNothing);
      expect(find.byKey(const Key('trip_chat_share_location')), findsNothing);
    });
  });
  testWidgets('Former driver loses screen access on reassignment and never sees the new history', (tester) async {
    await withTripUpdates(tester, (trips, _) async {
      await showChat(tester, actor: 'driver-1', trips: trips.stream,
        messages: [textMessage('a', 'creator-1', 'For driver A'),
          textMessage('b', 'creator-1', 'For driver B', assignment: 'driver-2')]);
      trips.add(chatTrip('accepted')); await pumpChat(tester);
      expect(find.text('For driver A'), findsOneWidget);
      expect(find.text('For driver B'), findsNothing);
      trips.add(TripPost.fromMap('trip-1', chatTrip('accepted').toFirestore()
        ..['acceptedDriverId'] = 'driver-2' ..['acceptedBidId'] = 'bid-2'));
      await pumpChat(tester);
      expect(find.text('For driver A'), findsNothing);
      expect(find.text('For driver B'), findsNothing);
      expect(find.textContaining('This chat is unavailable'), findsOneWidget);
    });
  });
  testWidgets('Creator retains A history while B history arrives after reopen and reassignment', (tester) async {
    await withTripUpdates(tester, (trips, messages) async {
      await showChat(tester, trips: trips.stream, messagesStream: messages.stream);
      trips.add(chatTrip('accepted'));
      await pumpChat(tester);
      final oldHistory = [textMessage('a', 'driver-1', 'For driver A'), locationMessage];
      messages.add(oldHistory);
      await pumpChat(tester);
      expect(find.text('For driver A'), findsOneWidget);
      expect(find.text('Location shared'), findsOneWidget);
      expect(find.text('For driver B'), findsNothing);

      trips.add(TripPost.fromMap('trip-1', chatTrip('open').toFirestore()
        ..['acceptedDriverId'] = null ..['acceptedBidId'] = null));
      await pumpChat(tester);
      expect(find.text('For driver A'), findsOneWidget);
      expect(find.byKey(const Key('trip_chat_send')), findsNothing);

      trips.add(TripPost.fromMap('trip-1', chatTrip('accepted').toFirestore()
        ..['acceptedDriverId'] = 'driver-2' ..['acceptedBidId'] = 'bid-2'));
      await pumpChat(tester);
      messages.add([...oldHistory,
        textMessage('b', 'driver-2', 'For driver B', assignment: 'driver-2')]);
      await pumpChat(tester);
      expect(find.text('For driver A'), findsOneWidget);
      expect(find.text('For driver B'), findsOneWidget);
      expect(find.text('Location shared'), findsOneWidget);
      expect(find.text('Open in Maps'), findsOneWidget);
    });
  });
  for (final enabled in [false, true]) {
    testWidgets('Location denied/disabled shows friendly error and never sends: enabled=$enabled', (tester) async {
      var sent = 0, lookups = 0;
      await showChat(tester, onSend: (_) async { sent++; }, location: TripLocationService(
        servicesEnabled: () async => enabled, checkPermission: () async => LocationPermission.denied,
        requestPermission: () async => LocationPermission.denied,
        locate: () async { lookups++; return const TripCoordinates(1, 2); }));
      await tester.tap(find.byKey(const Key('trip_chat_share_location'))); await pumpChat(tester);
      expect(find.textContaining(enabled ? 'permission was denied' : 'services are disabled'), findsOneWidget);
      expect(sent, 0); expect(lookups, 0);
    });
  }
  testWidgets('Manual location sends once, and delivery retry does not fetch GPS again', (tester) async {
    var lookups = 0;
    final sent = <TripChatMessage>[];
    await showChat(tester, onSend: (message) async { sent.add(message); if (sent.length == 1) throw StateError('offline'); },
      location: TripLocationService(servicesEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        locate: () async { lookups++; return const TripCoordinates(6.9271, 79.8612); }));
    expect(lookups, 0);
    await tester.tap(find.byKey(const Key('trip_chat_share_location'))); await pumpChat(tester);
    await tester.tap(find.byKey(const Key('trip_chat_retry_send'))); await pumpChat(tester);
    expect(lookups, 1); expect(sent.length, 2); expect(sent.first.id, sent.last.id);
    expect(sent.last.messageType, 'location'); expect(sent.last.text, isNull);
    expect(sent.last.latitude, 6.9271); expect(sent.last.longitude, 79.8612);
  });
  test('Permanent denial, one permission request, timeouts and maps failures are handled', () async {
    var requests = 0;
    final denied = TripLocationService(servicesEnabled: () async => true,
      checkPermission: () async => LocationPermission.denied,
      requestPermission: () async { requests++; return LocationPermission.denied; });
    await expectLater(denied.currentCoordinates(), throwsA(isA<TripLocationException>()));
    await expectLater(denied.currentCoordinates(), throwsA(isA<TripLocationException>()));
    expect(requests, 1);
    final blocked = TripLocationService(servicesEnabled: () async => true,
      checkPermission: () async => LocationPermission.deniedForever,
      requestPermission: () async { requests++; return LocationPermission.denied; });
    await expectLater(blocked.currentCoordinates(), throwsA(isA<TripLocationException>().having((e) => e.message, 'message', contains('blocked'))));
    expect(requests, 1);
    final timeout = TripLocationService(servicesEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      locate: () async => throw TimeoutException('lookup'), launch: (_) async => false);
    await expectLater(timeout.currentCoordinates(), throwsA(isA<TripLocationException>().having((e) => e.message, 'message', contains('timed out'))));
    await expectLater(timeout.openMaps(const TripCoordinates(1, 2)), throwsA(isA<TripLocationException>()));
  });
  testWidgets('Completion during GPS lookup prevents a location send', (tester) async {
    final coordinates = Completer<TripCoordinates>();
    var sent = 0, lookups = 0;
    await withTripUpdates(tester, (trips, _) async {
      await tester.pumpWidget(MaterialApp(home: TripChatScreen(tripPost: chatTrip('accepted'), actorUid: 'driver-1',
        tripStream: trips.stream, messagesStream: Stream.value([]), profileStream: Stream.value(null),
        messageIdFactory: () => 'location-race', onSend: (_) async { sent++; },
        locationService: TripLocationService(servicesEnabled: () async => true,
          checkPermission: () async => LocationPermission.whileInUse,
          locate: () { lookups++; return coordinates.future; }))));
      trips.add(chatTrip('accepted')); await pumpChat(tester);
      await tester.tap(find.byKey(const Key('trip_chat_share_location'))); await pumpChat(tester);
      expect(lookups, 1);
      expect(coordinates.isCompleted, isFalse);
      expect(sent, 0);
      trips.add(chatTrip('completed')); await pumpChat(tester);
      expect(find.text('Chat history is read-only.'), findsOneWidget);
      expect(find.byKey(const Key('trip_chat_share_location')), findsNothing);
      coordinates.complete(const TripCoordinates(6.9271, 79.8612)); await pumpChat(tester);
      expect(sent, 0);
      expect(find.text('The trip changed. No location was sent.'), findsOneWidget);
      expect(find.byKey(const Key('trip_chat_share_location')), findsNothing);
      expect(lookups, 1);
    }, coordinates: coordinates);
  });
  testWidgets('Firestore read errors are shown without exposing technical details', (tester) async {
    await showChat(tester, messagesStream: Stream.error(StateError('private diagnostic')));
    expect(find.textContaining('Could not load messages'), findsOneWidget);
    expect(find.text('Retry Messages'), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
  });
}
