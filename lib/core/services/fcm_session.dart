/// Independent of Firebase/plugins so session races can be tested deterministically.
abstract interface class FcmTokenPort {
  Future<String?> prepareToken(String uid);
  Future<void> save(String uid, String token);
  Future<void> detach(String uid);
}

class FcmSession {
  FcmSession(this.port, {this.onUserChanged});
  final FcmTokenPort port;
  final void Function(String?)? onUserChanged;
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
    if (uid != next) {
      onUserChanged?.call(next);
    }
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
    onUserChanged?.call(null);
    uid = null;
    _generation++;
    return _enqueue(() => port.detach(actor));
  }
}

class TripChatPushIntent {
  const TripChatPushIntent(this.uid, this.tripId, {this.type = 'trip_chat', this.sessionEpoch = 0, this.paymentId});
  final String uid, tripId;
  final String type;
  final String? paymentId;
  // Preserve the Stage 12A constructor; for workflow types this is a resource ID.
  String get resourceId => tripId;
  bool get isWorkflow => workflowBodies.containsKey(type);
  bool get isSupport => type.startsWith('support_');
  bool get isPayment => type.startsWith('payment_');
  final int sessionEpoch;
  bool belongsTo(String? currentUid, int currentEpoch) => uid == currentUid && sessionEpoch == currentEpoch;
  static const bodies = <String, String>{
    'trip_chat': 'You have a new trip message',
    'new_bid': 'You received a new bid for your trip.',
    'bid_accepted': 'Your bid was accepted.',
    'trip_start_requested': 'Your driver is ready to start the trip.',
    'trip_started': 'Your trip has started.',
    'trip_end_requested': 'Your driver requested to complete the trip.',
    'trip_completed': 'Your trip has been completed.',
    'trip_cancelled': 'The trip was cancelled by the trip creator.',
    'trip_reopened': 'The assigned driver cancelled. Your trip is open for bids again.',
  };
  static const workflowBodies = <String, String>{
    'support_new_request': 'A new support request needs review.',
    'support_admin_reply': 'You have a new support reply.',
    'support_user_reply': 'A support request has a new reply.',
    'registration_submitted': 'A new registration application is ready for review.',
    'registration_correction_required': 'Your registration application needs an update.',
    'registration_rejected': 'Your registration application has been reviewed.',
    'registration_approved': 'Your Ceylon Travel account has been approved.',
    'registration_driver_approved': 'Your driver application has been approved. Complete the remaining account steps.',
    'identity_verified': 'Your identity verification has been completed.',
    'identity_action_required': 'Your identity verification needs attention.',
    'payment_submitted': 'A driver payment is ready for review.',
    'payment_verified': 'Your registration payment has been verified.',
    'payment_rejected': 'Your registration payment needs attention.',
    'membership_activated': 'Your driver account is now active.',
    'founding_offer_closed': 'The founding driver offer has closed.',
  };
  String get body => workflowBodies[type] ?? bodies[type]!;
  Map<String, String> get routingData => {'type': type,
    if (!isWorkflow) 'tripId': tripId
    else if (isSupport) 'supportRequestId': resourceId
    else if (type == 'founding_offer_closed') 'eventId': resourceId
    else 'accountUid': resourceId,
    'paymentId': ?paymentId};
  bool get opensBids => type == 'new_bid' || type == 'trip_reopened';

  /// Only call with freshly fetched server state, never notification data.
  bool allows(String? currentUid, Map<String, dynamic> trip) {
    if (currentUid != uid) {
      return false;
    }
    final creator = trip['creatorId'];
    final driver = trip['acceptedDriverId'];
    final bid = trip['acceptedBidId'];
    final status = trip['status'];
    final assigned = creator is String && creator.isNotEmpty &&
        driver is String && driver.isNotEmpty && creator != driver &&
        bid is String && bid.isNotEmpty;
    if (opensBids) {
      return creator == uid && status == 'open';
    }
    if (!assigned) {
      return false;
    }
    switch (type) {
      case 'trip_chat':
        return (creator == uid || driver == uid) &&
            ['accepted', 'start_requested', 'in_progress', 'end_requested', 'completed', 'cancelled'].contains(status);
      case 'bid_accepted':
        return driver == uid && ['accepted', 'start_requested', 'in_progress', 'end_requested', 'completed'].contains(status);
      case 'trip_start_requested':
        return creator == uid && ['start_requested', 'in_progress', 'end_requested', 'completed'].contains(status);
      case 'trip_end_requested':
        return creator == uid && ['end_requested', 'completed'].contains(status);
      case 'trip_started':
        return (creator == uid || driver == uid) && ['in_progress', 'end_requested', 'completed'].contains(status);
      case 'trip_completed':
        return (creator == uid || driver == uid) && status == 'completed';
      case 'trip_cancelled':
        // Current cancellation clears assignment: safely fall back to home.
        return driver == uid && status == 'cancelled';
      default:
        return false;
    }
  }

  static TripChatPushIntent? parse(String? uid, Map<String, dynamic> data, {int sessionEpoch = 0}) {
    final type = data['type'];
    if (workflowBodies.containsKey(type)) {
      final name = type as String;
      final resource = data[name.startsWith('support_') ? 'supportRequestId' :
        name == 'founding_offer_closed' ? 'eventId' : 'accountUid'];
      final payment = data['paymentId'];
      if (uid == null || uid.isEmpty || !_validId(resource) ||
          (name.startsWith('payment_') && !_validId(payment)) ||
          (name == 'founding_offer_closed' && resource != 'founding_offer_closed')) {
        return null;
      }
      return TripChatPushIntent(uid, resource as String, type: name, sessionEpoch: sessionEpoch,
        paymentId: name.startsWith('payment_') ? payment as String : null);
    }
    final trip = data['tripId'];
    if (uid == null || uid.isEmpty || !bodies.containsKey(data['type']) || trip is! String ||
        trip.isEmpty || trip.length > 1500 || trip.contains('/') || trip == '.' || trip == '..') {
      return null;
    }
    return TripChatPushIntent(uid, trip, type: data['type'] as String, sessionEpoch: sessionEpoch);
  }
  static bool _validId(Object? id) => id is String && id.isNotEmpty && id.length <= 1500 &&
      !id.contains('/') && id != '.' && id != '..';
}
