import 'reputation_summary.dart';
import 'app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../models/trip_post.dart';
import 'info_line.dart';

class TripPostCard extends StatelessWidget {
  const TripPostCard({
    super.key,
    required this.tripPost,
    this.onViewDetails,
    this.onSubmitBid,
  });

  final TripPost tripPost;
  final VoidCallback? onViewDetails;
  final VoidCallback? onSubmitBid;

  @override
  Widget build(BuildContext context) {
    final bool hasActions = onViewDetails != null || onSubmitBid != null;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 18),
      child: InkWell(
        onTap: onViewDetails,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppStatusChip(tripPost.status),
                  Text(tripPost.creatorTypeLabel, style: AppTextStyles.caption),
                ],
              ),
              if (tripPost.tripReference != null) Text(tripPost.tripReference!, style: AppTextStyles.caption),
              const SizedBox(height: 20),
              AppRoute(pickup: tripPost.pickup, destination: tripPost.drop),
              const Divider(height: 32),
              InfoLine(
                icon: Icons.calendar_month_outlined,
                text: tripPost.dateTime,
                emphasized: true,
              ),
              const SizedBox(height: 4),
              InfoLine(
                icon: Icons.person_outline,
                text: '${tripPost.creatorName} ? ${tripPost.postedByLabel}',
                emphasized: true,
              ),
              const SizedBox(height: 10),
              InfoLine(icon: Icons.group_outlined, text: tripPost.passengers),
              InfoLine(icon: Icons.luggage_outlined, text: tripPost.baggage),
              InfoLine(
                icon: Icons.directions_car_outlined,
                text: tripPost.vehiclePreference,
              ),
              ReputationSummary(uid: tripPost.creatorId, creator: true),
              if (hasActions) ...[
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onViewDetails != null)
                      TextButton(
                        onPressed: onViewDetails,
                        child: const Text('View Details'),
                      ),
                    if (onSubmitBid != null) ...[
                      FilledButton(
                        onPressed: onSubmitBid,
                        child: const Text('Submit Bid'),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
