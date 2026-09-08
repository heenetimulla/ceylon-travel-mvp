import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/services/trip_post_service.dart';
import '../../core/widgets/trip_post_card.dart';
import '../../core/widgets/user_identity_header.dart';
import '../auth/session_navigation.dart';
import '../trip/completed_trips_screen.dart';
import '../trip/create_trip_post_screen.dart';
import '../trip/creator_trip_posts_screen.dart';
import '../trip/trip_details_screen.dart';
import 'accepted_driver_trips_screen.dart';
import 'submit_bid_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late Stream<List<TripPost>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = TripPostService().watchDriverPosts();
  }

  void _retryPosts() {
    setState(() => _posts = TripPostService().watchDriverPosts());
  }

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
          const UserIdentityHeader(),
          const SizedBox(height: 20),
          const Text(
            'Open trip posts',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Drivers choose their own bid price. Bids stay private for the post creator.',
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
              subtitle: const Text('Post a hire for your customer.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openCreateHirePost(context),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFFE0F2F1),
            child: ListTile(
              leading: const Icon(Icons.assignment_turned_in_outlined),
              title: const Text('My accepted trips'),
              subtitle: const Text('View trips assigned to you.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AcceptedDriverTripsScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreatorTripPostsScreen()),
            ),
            icon: const Icon(Icons.list_alt_outlined),
            label: const Text('My hire posts'),
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
          StreamBuilder<List<TripPost>>(
            stream: _posts,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text('Could not load trip posts. Please try again.'),
                    TextButton(
                      onPressed: _retryPosts,
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              final posts = snapshot.data ?? const <TripPost>[];
              if (posts.isEmpty) {
                return const Text(
                  'No open trip posts are available right now.',
                );
              }
              return Column(
                children: [
                  for (final tripPost in posts)
                    TripPostCard(
                      tripPost: tripPost,
                      onViewDetails: () => _openTripDetails(context, tripPost),
                      onSubmitBid: () => _openSubmitBid(context, tripPost),
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
