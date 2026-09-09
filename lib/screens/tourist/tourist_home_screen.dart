import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
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
      appBar: AppPageAppBar(
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
        padding: appPagePadding(context),
        children: [
          const UserIdentityHeader(),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need a driver for your Sri Lanka trip?',
                  style: AppTextStyles.title,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Post your pickup, drop, passenger count, baggage, date and time. Drivers will send private bids.',
                  style: AppTextStyles.secondary,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ocean,
                    foregroundColor: AppColors.surface,
                  ),
                  onPressed: () => _openCreateTripPost(context),
                  child: const Text('Create Trip'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ocean,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  onPressed: () => _openCompletedTrips(context),
                  icon: const Icon(Icons.done_all_outlined),
                  label: const Text('Completed Trips'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const AppSectionHeader(
            'My Trips',
            spacious: true,
            subtitle: 'Your requests and current travel plans.',
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
                return const AppEmptyState(
                  title: 'Your next journey starts here',
                  message: "You haven't created any trip posts yet.",
                );
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
