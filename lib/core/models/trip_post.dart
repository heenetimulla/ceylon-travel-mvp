class TripPost {
  const TripPost({
    required this.creatorId,
    required this.creatorType,
    required this.creatorName,
    this.touristId,
    this.driverId,
    required this.pickup,
    required this.drop,
    required this.dateTime,
    required this.adults,
    required this.kids,
    required this.baggageCount,
    required this.passengers,
    required this.baggage,
    required this.vehiclePreference,
    required this.notes,
    required this.status,
  });

  final String creatorId;
  final String creatorType;
  final String creatorName;
  final String? touristId;
  final String? driverId;
  final String pickup;
  final String drop;
  final String dateTime;
  final int adults;
  final int kids;
  final int baggageCount;
  final String passengers;
  final String baggage;
  final String vehiclePreference;
  final String notes;
  final String status;

  String get creatorTypeLabel {
    switch (creatorType.toLowerCase()) {
      case 'driver':
        return 'Driver';
      case 'tourist':
      case 'user':
      default:
        return 'Tourist/User';
    }
  }

  String get postedByLabel => 'Posted by $creatorTypeLabel';
}
