import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../../core/models/completed_trip.dart';
import '../../core/widgets/info_line.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key, required this.completedTrip});

  final CompletedTrip completedTrip;

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  final TextEditingController commentController = TextEditingController();
  int selectedRating = 5;

  @override
  void dispose() {
    commentController.dispose();
    super.dispose();
  }

  void _submitRating() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo rating saved. Firebase saving comes in Week 3.'),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final CompletedTrip trip = widget.completedTrip;

    return Scaffold(
      appBar: AppPageAppBar(title: const Text('Rate Trip')),
      body: SafeArea(
        child: ListView(
          padding: appPagePadding(context),
          children: [
            Card(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Trip summary', style: AppTextStyles.section),
                    const SizedBox(height: 10),
                    Text(trip.route, style: AppTextStyles.cardTitle),
                    const SizedBox(height: 8),
                    InfoLine(
                      icon: Icons.local_taxi_outlined,
                      text: 'Driver: ${trip.driverName}',
                    ),
                    InfoLine(
                      icon: Icons.person_outline,
                      text: 'Customer: ${trip.touristName}',
                    ),
                    InfoLine(
                      icon: Icons.calendar_month_outlined,
                      text: trip.completedDate,
                    ),
                    InfoLine(
                      icon: Icons.payments_outlined,
                      text: trip.acceptedBidPrice,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              color: AppColors.softBlue,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Week 2 MVP', style: AppTextStyles.cardTitle),
                    SizedBox(height: 10),
                    InfoLine(
                      icon: Icons.people_outline,
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
            const SizedBox(height: 18),
            const Text('Star rating', style: AppTextStyles.cardTitle),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int value = 1; value <= 5; value++)
                  IconButton(
                    tooltip: '$value star rating',
                    onPressed: () {
                      setState(() {
                        selectedRating = value;
                      });
                    },
                    icon: Icon(
                      value <= selectedRating ? Icons.star : Icons.star_border,
                      color: AppColors.ocean,
                      size: 34,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: commentController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Comment',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.rate_review_outlined),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitRating,
                child: Text('Submit Rating'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
