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

  void _openBidList(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristBidListScreen(tripPost: tripPost),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasActions = showViewBids || showSubmitBid;

    return Scaffold(
      appBar: AppBar(title: const Text('Trip Details')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Chip(
                      label: Text(
                        tripPost.status,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: const Color(0xFFE0F2F1),
                      side: BorderSide.none,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${tripPost.pickup} -> ${tripPost.drop}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _DetailRow(
                      icon: Icons.my_location_outlined,
                      label: 'Pickup location',
                      value: tripPost.pickup,
                    ),
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'Drop location',
                      value: tripPost.drop,
                    ),
                    _DetailRow(
                      icon: Icons.calendar_month_outlined,
                      label: 'Date and time',
                      value: tripPost.dateTime,
                    ),
                    _DetailRow(
                      icon: Icons.person_outline,
                      label: 'Posted by',
                      value: tripPost.creatorName,
                    ),
                    _DetailRow(
                      icon: Icons.account_circle_outlined,
                      label: 'Creator type',
                      value: tripPost.creatorTypeLabel,
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
                    if (hasActions) ...[
                      const SizedBox(height: 18),
                      if (showViewBids)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _openBidList(context),
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('View Bids'),
                            ),
                          ),
                        ),
                      if (showViewBids && showSubmitBid)
                        const SizedBox(height: 10),
                      if (showSubmitBid)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _openSubmitBid(context),
                            icon: const Icon(Icons.local_taxi_outlined),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Submit Bid'),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
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
          Icon(icon, size: 22, color: const Color(0xFF0F766E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
