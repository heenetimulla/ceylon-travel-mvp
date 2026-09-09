import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../../core/models/bid.dart';
import '../../core/models/completed_trip.dart';
import '../../core/models/trip_post.dart';
import '../../core/widgets/info_line.dart';
import '../chat/trip_chat_screen.dart';
import 'completed_trips_screen.dart';

class PendingTripScreen extends StatefulWidget {
  const PendingTripScreen({
    super.key,
    required this.tripPost,
    required this.acceptedBid,
  });

  final TripPost tripPost;
  final Bid acceptedBid;

  @override
  State<PendingTripScreen> createState() => _PendingTripScreenState();
}

class _PendingTripScreenState extends State<PendingTripScreen> {
  bool isCompletedConfirmed = false;

  CompletedTrip get _completedTrip {
    return CompletedTrip(
      id: 'completed-${widget.acceptedBid.id}',
      route: '${widget.tripPost.pickup} -> ${widget.tripPost.drop}',
      driverName: widget.acceptedBid.driverName,
      touristName: 'Tourist / Customer',
      completedDate: widget.tripPost.dateTime,
      acceptedBidPrice: widget.acceptedBid.price,
      status: 'COMPLETED',
    );
  }

  void _openChat(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripChatScreen(
          tripPost: widget.tripPost,
          acceptedBid: widget.acceptedBid,
        ),
      ),
    );
  }

  void _openCompletedTrips(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CompletedTripsScreen(recentCompletedTrip: _completedTrip),
      ),
    );
  }

  void _confirmCompleted(BuildContext context) {
    setState(() {
      isCompletedConfirmed = true;
    });
    _showMessage(context, 'Trip Completed');
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final TripPost tripPost = widget.tripPost;
    final Bid acceptedBid = widget.acceptedBid;

    return Scaffold(
      appBar: AppPageAppBar(title: const Text('Pending Trip')),
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
                    Text(
                      '${tripPost.pickup} -> ${tripPost.drop}',
                      style: AppTextStyles.section,
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
                    const AppStatusChip('PENDING'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driver / customer info',
                      style: AppTextStyles.cardTitle,
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
              color: AppColors.softBlue,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trip rules', style: AppTextStyles.cardTitle),
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
              label: Text('Open Chat'),
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
              onPressed: () => _confirmCompleted(context),
              child: const Text('Confirm Completed'),
            ),
            if (isCompletedConfirmed) ...[
              const SizedBox(height: 10),
              Card(
                color: AppColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Trip completed',
                        style: AppTextStyles.cardTitle,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You can now open completed trips and add the Week 2 demo rating.',
                        style: AppTextStyles.secondary,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _openCompletedTrips(context),
                          icon: const Icon(Icons.done_all_outlined),
                          label: Text('Open Completed Trips'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
