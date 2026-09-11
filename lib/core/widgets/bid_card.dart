import 'reputation_summary.dart';
import 'app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../models/bid.dart';
import 'info_line.dart';

class BidCard extends StatelessWidget {
  const BidCard({
    super.key,
    required this.bid,
    this.onAccept,
    this.effectiveStatus,
    this.isSaving = false,
  });

  final Bid bid;
  final VoidCallback? onAccept;
  final String? effectiveStatus;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final status = effectiveStatus ?? bid.status;
    final bool canAccept =
        status == 'submitted' && onAccept != null && !isSaving;

    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.softBlue,
                  child: Icon(Icons.person_outline, color: AppColors.ocean),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(bid.driverName, style: AppTextStyles.cardTitle),
                      const SizedBox(height: 4),
                      Text(
                        'Rating at offer: ${bid.driverRating.toStringAsFixed(1)}',
                        style: AppTextStyles.secondary,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppStatusChip(status),
            const SizedBox(height: 16),
            Text(bid.price, style: AppTextStyles.title),
            const Text('Offered trip price', style: AppTextStyles.caption),
            const Divider(),
            InfoLine(
              icon: Icons.check_circle_outline,
              text: '${bid.completedTrips} completed trips at offer',
            ),
            InfoLine(
              icon: Icons.directions_car_outlined,
              text: 'Vehicle type: ${bid.vehicleType}',
            ),
            InfoLine(
              icon: Icons.info_outline,
              text: 'Vehicle: ${bid.vehicleDetails}',
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.pearl,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Vehicle registration',
                    style: AppTextStyles.caption,
                  ),
                  Text(
                    'Vehicle number: ${bid.vehicleNumber.isEmpty ? 'Not provided' : bid.vehicleNumber}',
                    style: AppTextStyles.cardTitle,
                  ),
                ],
              ),
            ),
            InfoLine(
              icon: Icons.schedule_outlined,
              text: 'Estimated trip duration: ${bid.estimatedTravelTime}',
            ),
            ReputationSummary(uid: bid.driverId),
            InfoLine(icon: Icons.message_outlined, text: bid.message),
            const SizedBox(height: 14),
            SizedBox(
              child: FilledButton(
                onPressed: canAccept ? onAccept : null,
                child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept Bid'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
