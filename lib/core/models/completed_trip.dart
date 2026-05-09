import 'rating.dart';

class CompletedTrip {
  const CompletedTrip({
    required this.id,
    required this.route,
    required this.driverName,
    required this.touristName,
    required this.completedDate,
    required this.acceptedBidPrice,
    required this.status,
    this.userRating,
    this.driverRating,
  });

  final String id;
  final String route;
  final String driverName;
  final String touristName;
  final String completedDate;
  final String acceptedBidPrice;
  final String status;
  final Rating? userRating;
  final Rating? driverRating;
}
