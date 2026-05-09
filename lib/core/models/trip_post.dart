class TripPost {
  const TripPost({
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
}
