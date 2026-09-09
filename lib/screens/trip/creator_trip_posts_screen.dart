import '../../core/widgets/app_components.dart';
import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/services/trip_post_service.dart';
import '../../core/widgets/trip_post_card.dart';
import 'trip_details_screen.dart';

class CreatorTripPostsScreen extends StatefulWidget {
  const CreatorTripPostsScreen({super.key});

  @override
  State<CreatorTripPostsScreen> createState() => _CreatorTripPostsScreenState();
}

class _CreatorTripPostsScreenState extends State<CreatorTripPostsScreen> {
  late Stream<List<TripPost>> _posts;

  @override
  void initState() {
    super.initState();
    _posts = TripPostService().watchCreatorPosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppPageAppBar(title: const Text('My hire posts')),
      body: StreamBuilder<List<TripPost>>(
        key: ObjectKey(_posts),
        stream: _posts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your hire posts.'),
                  TextButton(
                    onPressed: () => setState(() {
                      _posts = TripPostService().watchCreatorPosts();
                    }),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final posts = snapshot.data!;
          if (posts.isEmpty) {
            return const Center(
              child: AppEmptyState(
                title: 'Your hires, organized',
                message: "You haven't created any hire posts yet.",
              ),
            );
          }
          return ListView(
            padding: appPagePadding(context),
            children: [
              for (final trip in posts)
                TripPostCard(
                  tripPost: trip,
                  onViewDetails: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TripDetailsScreen(tripPost: trip, showViewBids: true),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
