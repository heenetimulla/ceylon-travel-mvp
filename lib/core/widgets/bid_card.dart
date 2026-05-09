import 'package:flutter/material.dart';

import '../models/bid.dart';
import 'info_line.dart';

class BidCard extends StatelessWidget {
  const BidCard({super.key, required this.bid, required this.onAccept});

  final Bid bid;
  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final String statusText = bid.status.toUpperCase();
    final bool canAccept = bid.status == 'submitted';

    return Card(
      color: Colors.white,
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
                  backgroundColor: Color(0xFFE0F2F1),
                  child: Icon(Icons.person_outline, color: Color(0xFF0F766E)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bid.driverName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rating ${bid.driverRating.toStringAsFixed(1)}',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    statusText,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: const Color(0xFFE0F2F1),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoLine(
              icon: Icons.check_circle_outline,
              text: '${bid.completedTrips} completed trips',
            ),
            InfoLine(
              icon: Icons.cancel_outlined,
              text:
                  '${bid.cancellationRate} cancellation rate from last 10 trips',
            ),
            InfoLine(
              icon: Icons.directions_car_outlined,
              text: bid.vehicleType,
            ),
            InfoLine(icon: Icons.payments_outlined, text: bid.price),
            InfoLine(
              icon: Icons.schedule_outlined,
              text: bid.estimatedTravelTime,
            ),
            InfoLine(icon: Icons.message_outlined, text: bid.message),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canAccept ? onAccept : null,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Accept Bid'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
