import 'package:cloud_firestore/cloud_firestore.dart';

import 'trip_post.dart';

class Bid {
  const Bid({
    required this.id,
    required this.tripId,
    required this.driverId,
    required this.driverName,
    required this.driverRating,
    required this.completedTrips,
    required this.cancellationRate,
    required this.priceAmount,
    required this.vehicleType,
    required this.vehicleDetails,
    required this.vehicleNumber,
    required this.estimatedTripMinutes,
    required this.message,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String tripId;
  final String driverId;
  final String driverName;
  final double driverRating;
  final int completedTrips;
  // Percentage points: 10 means 10%, matching the user profile value.
  final double cancellationRate;
  final int priceAmount;
  final String vehicleType;
  final String vehicleDetails;
  final String vehicleNumber;
  final int estimatedTripMinutes;
  final String message;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String effectiveStatusFor(TripPost trip) {
    if (trip.status == 'accepted') {
      return trip.acceptedBidId == id ? 'accepted' : 'closed';
    }
    return status;
  }

  String get price =>
      'LKR ${priceAmount.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (match) => '${match[1]},')}';

  String get cancellationRateLabel =>
      '${cancellationRate == cancellationRate.roundToDouble() ? cancellationRate.toStringAsFixed(0) : cancellationRate.toString()}%';

  String get estimatedTravelTime {
    final days = estimatedTripMinutes ~/ 1440;
    final hours = (estimatedTripMinutes % 1440) ~/ 60;
    final minutes = estimatedTripMinutes % 60;
    return [
      if (days > 0) '$days ${days == 1 ? 'day' : 'days'}',
      if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
      if (minutes > 0 || estimatedTripMinutes == 0)
        '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
    ].join(' ');
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    throw const FormatException('Invalid bid timestamp.');
  }

  factory Bid.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw const FormatException('Bid does not exist.');
    return Bid.fromMap(doc.id, data);
  }

  factory Bid.fromMap(String id, Map<String, dynamic> data) => Bid(
    id: id,
    tripId: data['tripId'] as String,
    driverId: data['driverId'] as String,
    driverName: data['driverName'] as String,
    driverRating: (data['driverRating'] as num).toDouble(),
    completedTrips: data['completedTrips'] as int,
    cancellationRate: (data['cancellationRate'] as num).toDouble(),
    priceAmount: data['priceAmount'] as int,
    vehicleType: data['vehicleType'] as String,
    vehicleDetails: data['vehicleDetails'] as String,
    // Read Stage 8 Task 1 bids without inventing an assigned vehicle number.
    vehicleNumber: data['vehicleNumber'] as String? ?? '',
    estimatedTripMinutes: data['estimatedTripMinutes'] as int,
    message: data['message'] as String,
    status: data['status'] as String,
    createdAt: _date(data['createdAt']),
    updatedAt: _date(data['updatedAt']),
  );

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'tripId': tripId,
    'driverId': driverId,
    'driverName': driverName,
    'driverRating': driverRating,
    'completedTrips': completedTrips,
    'cancellationRate': cancellationRate,
    'priceAmount': priceAmount,
    'vehicleType': vehicleType,
    'vehicleDetails': vehicleDetails,
    'vehicleNumber': vehicleNumber,
    'estimatedTripMinutes': estimatedTripMinutes,
    'message': message,
    'status': status,
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
  };

  Bid copyWith({String? status}) => Bid(
    id: id,
    tripId: tripId,
    driverId: driverId,
    driverName: driverName,
    driverRating: driverRating,
    completedTrips: completedTrips,
    cancellationRate: cancellationRate,
    priceAmount: priceAmount,
    vehicleType: vehicleType,
    vehicleDetails: vehicleDetails,
    vehicleNumber: vehicleNumber,
    estimatedTripMinutes: estimatedTripMinutes,
    message: message,
    status: status ?? this.status,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
