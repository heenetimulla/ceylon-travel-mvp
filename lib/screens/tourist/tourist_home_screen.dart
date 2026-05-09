import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/widgets/trip_post_card.dart';
import '../trip/trip_details_screen.dart';
import 'create_trip_post_screen.dart';

const List<TripPost> _touristExampleTripPosts = [
  TripPost(
    pickup: 'Bandaranaike Airport',
    drop: 'Ella',
    dateTime: '20 May 2026 • 8:30 AM',
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
    pickup: 'Galle Fort',
    drop: 'Mirissa',
    dateTime: '22 May 2026 • 10:00 AM',
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

class TouristHomeScreen extends StatelessWidget {
  const TouristHomeScreen({super.key});

  void _openCreateTripPost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTripPostScreen()),
    );
  }

  void _openTripDetails(BuildContext context, TripPost tripPost) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TripDetailsScreen(tripPost: tripPost, showViewBids: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tourist Dashboard'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need a driver for your Sri Lanka trip?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Post your pickup, drop, passenger count, baggage, date and time. Drivers will send private bids.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F766E),
                  ),
                  onPressed: () => _openCreateTripPost(context),
                  child: const Text('Create Trip Post'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Example open trip posts',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (final TripPost tripPost in _touristExampleTripPosts)
            TripPostCard(
              tripPost: tripPost,
              onViewDetails: () => _openTripDetails(context, tripPost),
            ),
        ],
      ),
    );
  }
}
