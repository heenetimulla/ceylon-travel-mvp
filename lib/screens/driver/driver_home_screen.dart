import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/widgets/trip_post_card.dart';
import '../auth/session_navigation.dart';
import '../trip/completed_trips_screen.dart';
import '../trip/create_trip_post_screen.dart';
import '../trip/trip_details_screen.dart';
import 'submit_bid_screen.dart';

const List<TripPost> _driverOpenTripPosts = [
  TripPost(
    creatorId: 'tourist-demo-1',
    creatorType: 'tourist',
    creatorName: 'Ayesha Perera',
    touristId: 'tourist-demo-1',
    pickup: 'Bandaranaike Airport',
    drop: 'Ella',
    dateTime: '20 May 2026 - 8:30 AM',
    adults: 2,
    kids: 1,
    baggageCount: 3,
    passengers: '2 adults, 1 kid',
    baggage: '3 bags',
    vehiclePreference: 'Van',
    notes: 'Need an English-speaking driver with space for luggage.',
    status: 'OPEN',
  ),
  TripPost(
    creatorId: 'driver-demo-1',
    creatorType: 'driver',
    creatorName: 'Driver Nimal',
    driverId: 'driver-demo-1',
    pickup: 'Galle Fort',
    drop: 'Mirissa',
    dateTime: '22 May 2026 - 10:00 AM',
    adults: 4,
    kids: 0,
    baggageCount: 2,
    passengers: '4 adults',
    baggage: '2 bags',
    vehiclePreference: 'Any',
    notes: 'Prefer a comfortable vehicle for a coastal route.',
    status: 'OPEN',
  ),
];

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  void _openTripDetails(BuildContext context, TripPost tripPost) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TripDetailsScreen(tripPost: tripPost, showSubmitBid: true),
      ),
    );
  }

  void _openCompletedTrips(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CompletedTripsScreen()),
    );
  }

  void _openCreateHirePost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTripPostScreen()),
    );
  }

  void _openSubmitBid(BuildContext context, TripPost tripPost) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SubmitBidScreen(tripPost: tripPost)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: const [LogoutButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Open trip posts',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Drivers choose their own bid price. Bids stay private for the tourist.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          Card(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(
                Icons.post_add_outlined,
                color: Color(0xFF0F766E),
              ),
              title: const Text('Create Hire Post'),
              subtitle: const Text(
                'Got a hire you cannot do? Post it for other drivers.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openCreateHirePost(context),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openCompletedTrips(context),
              icon: const Icon(Icons.done_all_outlined),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Completed Trips'),
              ),
            ),
          ),
          const SizedBox(height: 18),
          for (final TripPost tripPost in _driverOpenTripPosts)
            TripPostCard(
              tripPost: tripPost,
              onViewDetails: () => _openTripDetails(context, tripPost),
              onSubmitBid: () => _openSubmitBid(context, tripPost),
            ),
        ],
      ),
    );
  }
}
