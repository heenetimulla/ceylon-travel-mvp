import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/fcm_session.dart';

class _Tokens implements FcmTokenPort {
  Future<String?> Function(String) prepare = (_) async => 'device-token';
  final saved = <String>[];
  final detached = <String>[];
  @override
  Future<String?> prepareToken(String uid) => prepare(uid);
  @override
  Future<void> save(String uid, String token) async { saved.add('$uid:$token'); }
  @override
  Future<void> detach(String uid) async { detached.add(uid); }
}

void main() {
  test('login registers current token; refresh updates only current owner', () async {
    final port = _Tokens(); final session = FcmSession(port);
    await session.changeUser('a');
    await session.refreshToken('new-token');
    expect(port.saved, ['a:device-token', 'a:new-token']);
    await session.beforeLogout('a');
    await session.refreshToken('ignored');
    expect(port.detached, ['a']);
    expect(port.saved.length, 2);
  });
  test('late old-session token is not written during user switch', () async {
    final pending = Completer<String?>();
    final entered = Completer<void>();
    final port = _Tokens()..prepare = (uid) {
      if (uid == 'a') { entered.complete(); return pending.future; }
      return Future.value('new-owner-token');
    };
    final session = FcmSession(port);
    final old = session.changeUser('a');
    await entered.future;
    final next = session.changeUser('b');
    pending.complete('old-token');
    await old; await next;
    expect(port.saved, ['b:new-owner-token']);
  });
  test('logout invalidates in-flight registration before cleanup', () async {
    final pending = Completer<String?>();
    final entered = Completer<void>();
    final port = _Tokens()..prepare = (_) { entered.complete(); return pending.future; };
    final session = FcmSession(port);
    final registration = session.changeUser('a'); await entered.future;
    final logout = session.beforeLogout('a');
    pending.complete('stale'); await registration; await logout;
    expect(port.saved, isEmpty); expect(port.detached, ['a']);
  });
  test('unavailable token safely no-ops and failed lookup does not poison next login', () async {
    final port = _Tokens()..prepare = (_) async => null;
    final session = FcmSession(port);
    await session.changeUser('a'); expect(port.saved, isEmpty);
    port.prepare = (_) async => throw StateError('offline');
    await expectLater(session.changeUser('a'), completes);
    port.prepare = (_) async => 'recovered';
    await session.changeUser('a'); expect(port.saved, ['a:recovered']);
  });
  test('payload is only a session-bound intent, with strict type and path checks', () {
    expect(TripChatPushIntent.parse(null, {'type': 'trip_chat', 'tripId': 't'}), isNull);
    for (final bad in ['', '..', 'trip/other']) {
      expect(TripChatPushIntent.parse('a', {'type': 'trip_chat', 'tripId': bad}), isNull);
    }
    expect(TripChatPushIntent.parse('a', {'type': 'marketing', 'tripId': 't'}), isNull);
    final intent = TripChatPushIntent.parse('a', {'type': 'trip_chat', 'tripId': 't'})!;
    expect(intent.uid, 'a'); expect(intent.tripId, 't');
  });
}
