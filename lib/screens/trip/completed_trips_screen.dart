import 'package:flutter/material.dart';

import '../../core/models/completed_trip.dart';
import '../../core/models/rating.dart';
import '../../core/widgets/info_line.dart';
import '../rating/rating_screen.dart';

const List<CompletedTrip> _sampleCompletedTrips = [
  CompletedTrip(
    id: 'completed-1',
    route: 'Bandaranaike Airport -> Ella',
    driverName: 'Nimal Perera',
    touristName: 'Tourist / Customer',
    completedDate: '20 May 2026',
    acceptedBidPrice: 'LKR 42,000',
    status: 'COMPLETED',
  ),
  CompletedTrip(
    id: 'completed-2',
    route: 'Galle Fort -> Mirissa',
    driverName: 'Saman Jayasinghe',
    touristName: 'Asha Fernando',
    completedDate: '22 Apr 2026',
    acceptedBidPrice: 'LKR 18,500',
    status: 'COMPLETED',
    userRating: Rating(
      id: 'rating-1',
      tripId: 'completed-2',
      fromUserName: 'Asha Fernando',
      toUserName: 'Saman Jayasinghe',
      ratingValue: 5,
      comment: 'Comfortable drive and careful timing.',
      createdAtText: '22 Apr 2026',
    ),
  ),
];

class CompletedTripsScreen extends StatelessWidget {
  const CompletedTripsScreen({super.key, this.recentCompletedTrip});

  final CompletedTrip? recentCompletedTrip;

  List<CompletedTrip> get _completedTrips {
    final CompletedTrip? recentTrip = recentCompletedTrip;
    if (recentTrip == null) return _sampleCompletedTrips;

    return [
      recentTrip,
      for (final CompletedTrip trip in _sampleCompletedTrips)
        if (trip.id != recentTrip.id) trip,
    ];
  }

  void _openRating(BuildContext context, CompletedTrip trip) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RatingScreen(completedTrip: trip)),
    );
  }

  void _showDetails(BuildContext context, CompletedTrip trip) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Completed trip details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trip.route,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text('Driver: ${trip.driverName}'),
              Text('Customer: ${trip.touristName}'),
              Text('Completed date: ${trip.completedDate}'),
              Text('Accepted bid price: ${trip.acceptedBidPrice}'),
              Text('Status: ${trip.status}'),
              const SizedBox(height: 12),
              Text(_ratingStatusText(trip)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  static String _ratingStatusText(CompletedTrip trip) {
    final Rating? userRating = trip.userRating;
    final Rating? driverRating = trip.driverRating;

    if (userRating == null && driverRating == null) {
      return 'Rating status: Tourist and driver ratings pending';
    }

    final List<String> statuses = [];
    statuses.add(
      userRating == null
          ? 'Tourist rating pending'
          : 'Tourist rated ${userRating.ratingValue.toStringAsFixed(1)}',
    );
    statuses.add(
      driverRating == null
          ? 'Driver rating pending'
          : 'Driver rated ${driverRating.ratingValue.toStringAsFixed(1)}',
    );

    return 'Rating status: ${statuses.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final List<CompletedTrip> completedTrips = _completedTrips;

    return Scaffold(
      appBar: AppBar(title: const Text('Completed Trips')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Card(
              color: Color(0xFFE0F2F1),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Week 2 MVP rating rules',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    InfoLine(
                      icon: Icons.star_border,
                      text:
                          'Both tourist and driver can rate each other after trip completion.',
                    ),
                    InfoLine(
                      icon: Icons.update_outlined,
                      text:
                          'Average rating and completed trip count will be updated in Week 3 with Firebase.',
                    ),
                    InfoLine(
                      icon: Icons.storage_outlined,
                      text: 'Rating is UI only for now.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final CompletedTrip trip in completedTrips)
              _CompletedTripCard(
                trip: trip,
                ratingStatus: _ratingStatusText(trip),
                onRateTrip: () => _openRating(context, trip),
                onViewDetails: () => _showDetails(context, trip),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompletedTripCard extends StatelessWidget {
  const _CompletedTripCard({
    required this.trip,
    required this.ratingStatus,
    required this.onRateTrip,
    required this.onViewDetails,
  });

  final CompletedTrip trip;
  final String ratingStatus;
  final VoidCallback onRateTrip;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    trip.route,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Chip(
                  label: Text(
                    trip.status,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: const Color(0xFFE0F2F1),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 10),
            InfoLine(icon: Icons.local_taxi_outlined, text: trip.driverName),
            InfoLine(icon: Icons.person_outline, text: trip.touristName),
            InfoLine(
              icon: Icons.calendar_month_outlined,
              text: trip.completedDate,
            ),
            InfoLine(
              icon: Icons.payments_outlined,
              text: trip.acceptedBidPrice,
            ),
            InfoLine(icon: Icons.star_half_outlined, text: ratingStatus),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onRateTrip,
                    child: const Text('Rate Trip'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onViewDetails,
                    child: const Text('View Details'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
