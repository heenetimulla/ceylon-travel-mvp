import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/services/trip_post_service.dart';
import '../../core/widgets/trip_post_card.dart';
import '../../core/widgets/user_identity_header.dart';
import '../auth/session_navigation.dart';
import '../trip/completed_trips_screen.dart';
import '../trip/create_trip_post_screen.dart';
import '../trip/trip_details_screen.dart';

class TouristHomeScreen extends StatefulWidget {
  const TouristHomeScreen({super.key});

  @override
  State<TouristHomeScreen> createState() => _TouristHomeScreenState();
}

class _TouristHomeScreenState extends State<TouristHomeScreen> {
  late Stream<List<TripPost>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = TripPostService().watchTouristPosts();
  }

  void _retryPosts() {
    setState(() => _posts = TripPostService().watchTouristPosts());
  }

  void _openCreateTripPost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTripPostScreen()),
    );
  }

  void _openCompletedTrips(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CompletedTripsScreen()),
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
          const LogoutButton(),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const UserIdentityHeader(),
          const SizedBox(height: 20),
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
                  child: const Text('Create Trip / Hire Post'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  onPressed: () => _openCompletedTrips(context),
                  icon: const Icon(Icons.done_all_outlined),
                  label: const Text('Completed Trips'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'My trip posts',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<TripPost>>(
            stream: _posts,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text(
                      'Could not load your trip posts. Please try again.',
                    ),
                    TextButton(
                      onPressed: _retryPosts,
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              final posts = snapshot.data ?? const <TripPost>[];
              if (posts.isEmpty) {
                return const Text("You haven't created any trip posts yet.");
              }
              return Column(
                children: [
                  for (final tripPost in posts)
                    TripPostCard(
                      tripPost: tripPost,
                      onViewDetails: () => _openTripDetails(context, tripPost),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
