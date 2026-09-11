import 'trip_post.dart';

List<TripPost> orderedActiveTrips(Iterable<TripPost> trips) {
  final result = trips.where((trip) => const [
    'open', 'accepted', 'start_requested', 'in_progress', 'end_requested',
  ].contains(trip.status)).toList();
  result.sort((a, b) {
    final group = (a.status == 'open' ? 0 : 1).compareTo(b.status == 'open' ? 0 : 1);
    if (group != 0) return group;
    // Legacy documents without creation time sort last. Never use scheduled time.
    final time = (b.createdAt ?? DateTime.utc(1970)).compareTo(a.createdAt ?? DateTime.utc(1970));
    return time != 0 ? time : a.id.compareTo(b.id);
  });
  return result;
}
