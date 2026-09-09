import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../driver/submit_bid_screen.dart';
import '../tourist/tourist_bid_list_screen.dart';

class TripDetailsScreen extends StatelessWidget {
  const TripDetailsScreen({
    super.key,
    required this.tripPost,
    this.showViewBids = false,
    this.showSubmitBid = false,
    this.additionalDetails,
  });

  final TripPost tripPost;
  final bool showViewBids;
  final bool showSubmitBid;
  final Widget? additionalDetails;

  void _openSubmitBid(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SubmitBidScreen(tripPost: tripPost)),
    );
  }

  Future<void> _openBidList(BuildContext context) async {
    final withdrawn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TouristBidListScreen(tripPost: tripPost),
      ),
    );
    if (withdrawn == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasActions = showViewBids || showSubmitBid;

    return Scaffold(
      appBar: AppPageAppBar(title: const Text('Trip Details')),
      body: SafeArea(
        child: ListView(
          padding: appPagePadding(context),
          children: [
            AppInfoCard(
              children: [
                AppStatusChip(tripPost.status),
                const AppSectionHeader('Route'),
                AppRoute(pickup: tripPost.pickup, destination: tripPost.drop),
              ],
            ),
            AppInfoCard(
              children: [
                const AppSectionHeader('Schedule & passengers'),
                _DetailRow(
                  icon: Icons.calendar_month_outlined,
                  label: 'Date and time',
                  value: tripPost.dateTime,
                ),
                _DetailRow(
                  icon: Icons.group_outlined,
                  label: 'Adults count',
                  value: tripPost.adults.toString(),
                ),
                _DetailRow(
                  icon: Icons.child_care_outlined,
                  label: 'Kids count',
                  value: tripPost.kids.toString(),
                ),
                _DetailRow(
                  icon: Icons.luggage_outlined,
                  label: 'Baggage count',
                  value: tripPost.baggageCount.toString(),
                ),
              ],
            ),
            AppInfoCard(
              children: [
                const AppSectionHeader('Vehicle & notes'),
                _DetailRow(
                  icon: Icons.directions_car_outlined,
                  label: 'Vehicle preference',
                  value: tripPost.vehiclePreference,
                ),
                _DetailRow(
                  icon: Icons.notes_outlined,
                  label: 'Notes',
                  value: tripPost.notes,
                ),
              ],
            ),
            AppInfoCard(
              children: [
                const AppSectionHeader('Posted by'),
                _DetailRow(
                  icon: Icons.person_outline,
                  label: 'Name',
                  value: tripPost.creatorName,
                ),
                _DetailRow(
                  icon: Icons.account_circle_outlined,
                  label: 'Creator type',
                  value: tripPost.creatorTypeLabel,
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasActions) ...[
                  const SizedBox(height: 18),
                  if (showViewBids)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openBidList(context),
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text('View Bids'),
                      ),
                    ),
                  if (showViewBids && showSubmitBid) const SizedBox(height: 10),
                  if (showSubmitBid)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _openSubmitBid(context),
                        icon: const Icon(Icons.local_taxi_outlined),
                        label: Text('Submit Bid'),
                      ),
                    ),
                ],
              ],
            ),
            ?additionalDetails,
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: AppColors.ocean),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.cardTitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
