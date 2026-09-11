import '../auth/account_screen.dart';
import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/models/active_trip_order.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../trip/lifecycle_trip_screen.dart';
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
  const DriverHomeScreen({super.key, this.postsStream, this.loadProfile});
  final Stream<List<TripPost>>? postsStream;
  final Future<Map<String, dynamic>?> Function()? loadProfile;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late Stream<List<TripPost>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = widget.postsStream ?? TripPostService().watchDriverDashboardPosts();
  }

  void _retryPosts() {
    setState(() => _posts = widget.postsStream ?? TripPostService().watchDriverDashboardPosts());
  }

  void _openTripDetails(BuildContext context, TripPost tripPost) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripPost.assignedStatuses.contains(tripPost.status)
            ? LifecycleTripScreen(tripId: tripPost.id)
            : TripDetailsScreen(tripPost: tripPost,
                showViewBids: tripPost.creatorId == FirebaseAuth.instance.currentUser?.uid,
                showSubmitBid: tripPost.creatorId != FirebaseAuth.instance.currentUser?.uid),
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
      appBar: AppPageAppBar(
        title: const Text('Driver Dashboard'),
        actions: [IconButton(tooltip: 'Account & Support', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountScreen())), icon: const Icon(Icons.account_circle_outlined)), const LogoutButton()],
      ),
      body: ListView(
        padding: appPagePadding(context),
        children: [
          UserIdentityHeader(loadProfile: widget.loadProfile),
          const SizedBox(height: 20),
          const Text('Your driver workspace', style: AppTextStyles.section),
          const SizedBox(height: 8),
          const Text(
            'Drivers choose their own bid price. Bids stay private for the post creator.',
            style: AppTextStyles.secondary,
          ),
          const SizedBox(height: 14),
          const AppSectionHeader(
            'Partner Hires',
            spacious: true,
            subtitle: 'Create and manage hires for your customers.',
          ),
          Card(
            color: AppColors.surface,
            child: ListTile(
              leading: const Icon(
                Icons.post_add_outlined,
                color: AppColors.ocean,
              ),
              title: const Text('Create Hire Post'),
              subtitle: const Text('Post a hire for your customer.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openCreateHirePost(context),
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
          const AppSectionHeader('Assigned Work', spacious: true),
          Card(
            color: AppColors.softBlue,
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _openCompletedTrips(context),
              icon: const Icon(Icons.done_all_outlined),
              label: Text('Completed Trips'),
            ),
          ),
          const SizedBox(height: 18),
          const AppSectionHeader(
            'Available Trips & Active Hires',
            spacious: true,
            subtitle: 'Open requests first, followed by your active hires and assigned trips.',
          ),
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
              final posts = orderedActiveTrips(snapshot.data ?? const <TripPost>[]);
              if (posts.isEmpty) {
                return const AppEmptyState(
                  title: 'No trips available',
                  message:
                      'No open or active trips are available right now. Check back for new requests.',
                );
              }
              return Column(
                children: [
                  for (final tripPost in posts)
                    TripPostCard(
                      tripPost: tripPost,
                      onViewDetails: () => _openTripDetails(context, tripPost),
                      onSubmitBid: tripPost.status == 'open' && Firebase.apps.isNotEmpty &&
                          tripPost.creatorId != FirebaseAuth.instance.currentUser?.uid
                          ? () => _openSubmitBid(context, tripPost) : null,
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
