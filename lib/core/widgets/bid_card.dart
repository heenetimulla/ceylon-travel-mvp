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
    final String statusText = status.replaceAll('_', ' ').toUpperCase();
    final bool canAccept =
        status == 'submitted' && onAccept != null && !isSaving;

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
                  '${bid.cancellationRateLabel} cancellation rate from last 10 trips',
            ),
            InfoLine(
              icon: Icons.directions_car_outlined,
              text: 'Vehicle type: ${bid.vehicleType}',
            ),
            InfoLine(
              icon: Icons.info_outline,
              text: 'Vehicle: ${bid.vehicleDetails}',
            ),
            InfoLine(
              icon: Icons.confirmation_number_outlined,
              text:
                  'Vehicle number: ${bid.vehicleNumber.isEmpty ? 'Not provided' : bid.vehicleNumber}',
            ),
            InfoLine(icon: Icons.payments_outlined, text: bid.price),
            InfoLine(
              icon: Icons.schedule_outlined,
              text: 'Estimated trip duration: ${bid.estimatedTravelTime}',
            ),
            InfoLine(icon: Icons.message_outlined, text: bid.message),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canAccept ? onAccept : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Accept Bid'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
