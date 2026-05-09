class Bid {
  const Bid({
    required this.id,
    required this.driverName,
    required this.driverRating,
    required this.completedTrips,
    required this.cancellationRate,
    required this.vehicleType,
    required this.price,
    required this.estimatedTravelTime,
    required this.message,
    required this.status,
  });

  final String id;
  final String driverName;
  final double driverRating;
  final int completedTrips;
  final String cancellationRate;
  final String vehicleType;
  final String price;
  final String estimatedTravelTime;
  final String message;
  final String status;

  Bid copyWith({String? status}) {
    return Bid(
      id: id,
      driverName: driverName,
      driverRating: driverRating,
      completedTrips: completedTrips,
      cancellationRate: cancellationRate,
      vehicleType: vehicleType,
      price: price,
      estimatedTravelTime: estimatedTravelTime,
      message: message,
      status: status ?? this.status,
    );
  }
}
