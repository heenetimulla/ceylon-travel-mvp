import 'trip_post.dart';

enum LifecycleAction { requestStart, confirmStart, requestEnd, confirmEnd }

/// Role/state preflight only. Firestore request.time enforces confirmation deadlines.
void validateLifecycle(TripPost trip, String uid, LifecycleAction action) {
  final driver = trip.acceptedDriverId;
  if (driver == null || driver.isEmpty || trip.acceptedBidId == null ||
      trip.acceptedBidId!.isEmpty || driver == trip.creatorId ||
      (uid != driver && uid != trip.creatorId)) {
    throw StateError('Only the trip creator and accepted driver can manage this trip.');
  }
  switch (action) {
    case LifecycleAction.requestStart:
      if (uid != driver || trip.status != 'accepted') throw StateError('Only the accepted driver can request start of an accepted trip.');
    case LifecycleAction.requestEnd:
      if (uid != driver || trip.status != 'in_progress') throw StateError('Only the accepted driver can request end of an in-progress trip.');
    case LifecycleAction.confirmStart:
      if (uid != trip.creatorId || trip.status != 'start_requested' || trip.startAutoStartAt == null) throw StateError('Start confirmation is no longer available.');
    case LifecycleAction.confirmEnd:
      if (uid != trip.creatorId || trip.status != 'end_requested' || trip.endAutoCompleteAt == null) throw StateError('End confirmation is no longer available.');
  }
}
