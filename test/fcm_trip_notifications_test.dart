import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/services/fcm_session.dart';
import 'package:taxi_app/core/widgets/fcm_navigation_host.dart';
import 'package:taxi_app/screens/chat/trip_chat_screen.dart';
import 'package:taxi_app/screens/tourist/tourist_bid_list_screen.dart';
import 'package:taxi_app/screens/trip/lifecycle_trip_screen.dart';

class _Tokens implements FcmTokenPort {
  @override
  Future<String?> prepareToken(String uid) async => null;
  @override
  Future<void> save(String uid, String token) async {}
  @override
  Future<void> detach(String uid) async {}
}

void main() {
  final assigned = <String, dynamic>{'creatorId': 'creator',
    'acceptedDriverId': 'driver', 'acceptedBidId': 'driver', 'status': 'accepted'};
  final trip = TripPost(id: 't', creatorId: 'creator', creatorType: 'tourist',
    creatorName: 'Private', postType: 'trip', postOrigin: 'direct',
    pickupLocationText: 'Private', dropLocationText: 'Private',
    scheduledAt: DateTime.utc(2026), adultsCount: 1, kidsCount: 0,
    baggageCount: 0, vehiclePreference: 'car', notes: '', status: 'accepted',
    acceptedDriverId: 'driver', acceptedBidId: 'driver');

  for (final type in TripChatPushIntent.bodies.keys) {
    test('$type parses with strict session/path binding and fixed private body', () {
      final intent = TripChatPushIntent.parse('driver', {'type': type, 'tripId': 't',
        'body': 'PRIVATE MESSAGE', 'recipient': 'unrelated', 'priceAmount': 5000})!;
      expect(intent.type, type);
      expect(intent.tripId, 't');
      expect(intent.uid, 'driver');
      expect(intent.body, isNot(contains('PRIVATE')));
      expect(intent.allows('another-account', assigned), isFalse);
      expect(intent.allows(null, assigned), isFalse);
      expect(TripChatPushIntent.parse(null, {'type': type, 'tripId': 't'}), isNull);
      expect(TripChatPushIntent.parse('driver', {'type': type, 'tripId': '../t'}), isNull);
    });
  }

  test('bid/reopen intents authorize only current creator of an open trip', () {
    for (final type in ['new_bid', 'trip_reopened']) {
      final creator = TripChatPushIntent('creator', 't', type: type);
      final open = {'creatorId': 'creator', 'driverId': 'partner', 'status': 'open'};
      expect(creator.allows('creator', open), isTrue);
      expect(creator.opensBids, isTrue);
      expect(creator.allows('creator', assigned), isFalse);
      expect(TripChatPushIntent('partner', 't', type: type).allows('partner', open), isFalse);
      expect(notificationDestination(creator, trip), isA<TouristBidListScreen>());
    }
  });

  test('accepted bid uses performing driver, not creator, losing or legacy driverId', () {
    for (final uid in ['creator', 'losing', 'partner']) {
      expect(TripChatPushIntent(uid, 't', type: 'bid_accepted')
          .allows(uid, {...assigned, 'driverId': 'partner'}), isFalse);
    }
    const intent = TripChatPushIntent('driver', 't', type: 'bid_accepted');
    expect(intent.allows('driver', assigned), isTrue);
    expect(intent.allows('driver', {...assigned, 'acceptedDriverId': 'replacement'}), isFalse);
    expect(notificationDestination(intent, trip), isA<LifecycleTripScreen>());
  });

  for (final item in [
    ('trip_start_requested', 'start_requested'), ('trip_end_requested', 'end_requested'),
  ]) {
    test('${item.$1} permits creator confirmation flow only', () {
      final state = {...assigned, 'status': item.$2};
      expect(TripChatPushIntent('creator', 't', type: item.$1).allows('creator', state), isTrue);
      expect(TripChatPushIntent('driver', 't', type: item.$1).allows('driver', state), isFalse);
    });
  }
  test('started/completed routes validate current participants and current lifecycle', () {
    for (final item in [('trip_started', 'in_progress'), ('trip_completed', 'completed')]) {
      for (final uid in ['creator', 'driver']) {
        final intent = TripChatPushIntent(uid, 't', type: item.$1);
        expect(intent.allows(uid, {...assigned, 'status': item.$2}), isTrue);
        expect(intent.allows(uid, assigned), isFalse);
        expect(notificationDestination(intent, trip), isA<LifecycleTripScreen>());
      }
      expect(TripChatPushIntent('old', 't', type: item.$1)
          .allows('old', {...assigned, 'status': item.$2}), isFalse);
    }
  });
  test('cancelled assignment cannot reopen private detail; chat destination preserved', () {
    const intent = TripChatPushIntent('driver', 't', type: 'trip_cancelled');
    expect(intent.allows('driver', {'creatorId': 'creator', 'status': 'cancelled',
      'acceptedDriverId': null, 'acceptedBidId': null}), isFalse);
    const chat = TripChatPushIntent('driver', 't');
    expect(chat.allows('driver', assigned), isTrue);
    expect(notificationDestination(chat, trip), isA<TripChatScreen>());
  });
  test('session change and logout clear queued intents synchronously', () async {
    TripChatPushIntent? pending;
    final session = FcmSession(_Tokens(), onUserChanged: (_) => pending = null);
    await session.changeUser('driver');
    pending = const TripChatPushIntent('driver', 't', type: 'bid_accepted');
    final switchUser = session.changeUser('other');
    expect(pending, isNull);
    await switchUser;
    pending = const TripChatPushIntent('other', 't', type: 'new_bid');
    final logout = session.beforeLogout('other');
    expect(pending, isNull);
    await logout;
  });
  test('switching away and back cannot reuse an earlier session navigation result', () {
    final intent = TripChatPushIntent.parse('driver',
      {'type': 'bid_accepted', 'tripId': 't'}, sessionEpoch: 1)!;
    expect(intent.belongsTo('driver', 1), isTrue);
    expect(intent.belongsTo('other', 2), isFalse);
    expect(intent.belongsTo('driver', 3), isFalse);
    expect(intent.belongsTo(null, 2), isFalse);
  });
}
