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
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        onTap: onViewDetails,
        child: Padding(
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 8),
              Text(
                '${tripPost.pickup} -> ${tripPost.drop}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              InfoLine(
                icon: Icons.calendar_month_outlined,
                text: tripPost.dateTime,
              ),
              InfoLine(
                icon: Icons.person_outline,
                text: tripPost.postedByLabel,
              ),
              InfoLine(icon: Icons.group_outlined, text: tripPost.passengers),
              InfoLine(icon: Icons.luggage_outlined, text: tripPost.baggage),
              if (hasActions) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (onViewDetails != null)
                      TextButton(
                        onPressed: onViewDetails,
                        child: const Text('View Details'),
                      ),
                    if (onSubmitBid != null) ...[
                      const SizedBox(width: 8),
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
