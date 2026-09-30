/// Independent of Firebase/plugins so session races can be tested deterministically.
abstract interface class FcmTokenPort {
  Future<String?> prepareToken(String uid);
  Future<void> save(String uid, String token);
  Future<void> detach(String uid);
}

class FcmSession {
  FcmSession(this.port);
  final FcmTokenPort port;
  String? uid;
  int _generation = 0;
  Future<void> _tail = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() work) {
    final result = _tail.then((_) => work());
    // Keep later session work running even if the platform/network failed.
    _tail = result.catchError((Object _) {});
    return _tail;
  }

  Future<void> changeUser(String? next) {
    uid = next;
    final generation = ++_generation;
    return _enqueue(() async {
      if (next == null || generation != _generation) return;
      final token = await port.prepareToken(next);
      if (generation != _generation || uid != next || token == null || token.isEmpty) return;
      await port.save(next, token);
    });
  }

  Future<void> refreshToken(String token) {
    final actor = uid;
    final generation = _generation;
    return _enqueue(() async {
      if (actor == null || actor != uid || generation != _generation || token.isEmpty) return;
      await port.save(actor, token);
    });
  }

  /// Call BEFORE Firebase signOut, while owner-only token deletion is authorized.
  Future<void> beforeLogout(String actor) {
    uid = null;
    _generation++;
    return _enqueue(() => port.detach(actor));
  }
}

class TripChatPushIntent {
  const TripChatPushIntent(this.uid, this.tripId);
  final String uid, tripId;

  static TripChatPushIntent? parse(String? uid, Map<String, dynamic> data) {
    final trip = data['tripId'];
    if (uid == null || uid.isEmpty || data['type'] != 'trip_chat' || trip is! String ||
        trip.isEmpty || trip.length > 1500 || trip.contains('/') || trip == '.' || trip == '..') {
      return null;
    }
    return TripChatPushIntent(uid, trip);
  }
}
