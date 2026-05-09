import 'package:flutter/material.dart';

import '../../core/models/bid.dart';
import '../../core/models/trip_post.dart';
import '../../core/widgets/info_line.dart';
import '../chat/trip_chat_screen.dart';

class PendingTripScreen extends StatelessWidget {
  const PendingTripScreen({
    super.key,
    required this.tripPost,
    required this.acceptedBid,
  });

  final TripPost tripPost;
  final Bid acceptedBid;

  void _openChat(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TripChatScreen(tripPost: tripPost, acceptedBid: acceptedBid),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pending Trip')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${tripPost.pickup} -> ${tripPost.drop}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    InfoLine(
                      icon: Icons.calendar_month_outlined,
                      text: tripPost.dateTime,
                    ),
                    InfoLine(
                      icon: Icons.group_outlined,
                      text: tripPost.passengers,
                    ),
                    InfoLine(
                      icon: Icons.luggage_outlined,
                      text: tripPost.baggage,
                    ),
                    const SizedBox(height: 10),
                    const Chip(
                      label: Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: Color(0xFFE0F2F1),
                      side: BorderSide.none,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driver / customer info',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    InfoLine(
                      icon: Icons.local_taxi_outlined,
                      text:
                          '${acceptedBid.driverName} - Rating ${acceptedBid.driverRating.toStringAsFixed(1)}',
                    ),
                    InfoLine(
                      icon: Icons.check_circle_outline,
                      text: '${acceptedBid.completedTrips} completed trips',
                    ),
                    InfoLine(
                      icon: Icons.cancel_outlined,
                      text:
                          '${acceptedBid.cancellationRate} cancellation rate from last 10 trips',
                    ),
                    InfoLine(
                      icon: Icons.person_outline,
                      text: 'Customer: Tourist / Customer',
                    ),
                    InfoLine(
                      icon: Icons.payments_outlined,
                      text: 'Accepted bid price: ${acceptedBid.price}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Card(
              color: Color(0xFFE0F2F1),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip rules',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 10),
                    InfoLine(
                      icon: Icons.play_circle_outline,
                      text: 'Driver starts and ends the trip.',
                    ),
                    InfoLine(
                      icon: Icons.timer_outlined,
                      text: 'User must confirm within 3 minutes.',
                    ),
                    InfoLine(
                      icon: Icons.autorenew_outlined,
                      text: 'Auto-confirm/auto-complete after 15 minutes.',
                    ),
                    InfoLine(
                      icon: Icons.cancel_outlined,
                      text: 'Both sides can cancel.',
                    ),
                    InfoLine(
                      icon: Icons.warning_amber_outlined,
                      text: 'Cancellations count against account.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openChat(context),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Open Chat'),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => _showMessage(context, 'Start Trip Requested'),
              child: const Text('Start Trip'),
            ),
            OutlinedButton(
              onPressed: () => _showMessage(context, 'Trip Start Confirmed'),
              child: const Text('Confirm Start'),
            ),
            OutlinedButton(
              onPressed: () => _showMessage(context, 'End Trip Requested'),
              child: const Text('End Trip'),
            ),
            OutlinedButton(
              onPressed: () => _showMessage(context, 'Trip Completed'),
              child: const Text('Confirm Completed'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _showMessage(context, 'Demo cancellation recorded'),
              child: const Text('Cancel Trip'),
            ),
          ],
        ),
      ),
    );
  }
}
