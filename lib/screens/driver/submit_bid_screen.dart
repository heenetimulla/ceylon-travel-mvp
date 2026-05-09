import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/widgets/info_line.dart';

class SubmitBidScreen extends StatefulWidget {
  const SubmitBidScreen({super.key, required this.tripPost});

  final TripPost tripPost;

  @override
  State<SubmitBidScreen> createState() => _SubmitBidScreenState();
}

class _SubmitBidScreenState extends State<SubmitBidScreen> {
  final TextEditingController bidPriceController = TextEditingController();
  final TextEditingController vehicleTypeController = TextEditingController();
  final TextEditingController travelTimeController = TextEditingController();
  final TextEditingController messageController = TextEditingController();

  @override
  void dispose() {
    bidPriceController.dispose();
    vehicleTypeController.dispose();
    travelTimeController.dispose();
    messageController.dispose();
    super.dispose();
  }

  void _submitBid() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo bid submitted. Firebase saving comes in Week 3.'),
      ),
    );

    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final TripPost tripPost = widget.tripPost;

    return Scaffold(
      appBar: AppBar(title: const Text('Submit Bid')),
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
                    const Text(
                      'Trip summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${tripPost.pickup} → ${tripPost.drop}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: bidPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Bid price',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vehicleTypeController,
              decoration: const InputDecoration(
                labelText: 'Vehicle type',
                hintText: 'Car / Van / SUV',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: travelTimeController,
              decoration: const InputDecoration(
                labelText: 'Estimated travel time',
                hintText: 'Example: 5 hours',
                prefixIcon: Icon(Icons.schedule_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Short message',
                hintText: 'Example: I can pick you up on time.',
                prefixIcon: Icon(Icons.message_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submitBid,
              icon: const Icon(Icons.send),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Submit Bid'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
