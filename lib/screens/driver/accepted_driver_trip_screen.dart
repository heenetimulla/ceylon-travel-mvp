import 'package:flutter/material.dart';

import '../../core/models/bid.dart';
import '../../core/models/trip_post.dart';
import '../../core/services/bid_service.dart';
import '../../core/widgets/info_line.dart';
import '../../core/widgets/trip_cancellation_button.dart';
import '../trip/trip_details_screen.dart';

class AcceptedDriverTripScreen extends StatefulWidget {
  const AcceptedDriverTripScreen({
    super.key,
    required this.tripPost,
    this.watchBid,
  });

  final TripPost tripPost;
  final Stream<Bid?> Function(TripPost)? watchBid;

  @override
  State<AcceptedDriverTripScreen> createState() =>
      _AcceptedDriverTripScreenState();
}

class _AcceptedDriverTripScreenState extends State<AcceptedDriverTripScreen> {
  late Stream<Bid?> _bid;

  void _subscribe() {
    // This service watches bids/{current UID}, never the bids collection.
    _bid =
        widget.watchBid?.call(widget.tripPost) ??
        BidService().watchDriverBid(widget.tripPost);
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant AcceptedDriverTripScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripPost.id != widget.tripPost.id ||
        oldWidget.watchBid != widget.watchBid) {
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.tripPost;
    // The own-bid stream verifies the active driver before showing cancellation.
    return TripDetailsScreen(
      tripPost: trip,
      additionalDetails: Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: StreamBuilder<Bid?>(
            key: ObjectKey(_bid),
            stream: _bid,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Column(
                  children: [
                    Text(
                      error is BidServiceException
                          ? error.message
                          : 'Could not load your accepted bid. Please try again.',
                    ),
                    TextButton(
                      onPressed: () => setState(_subscribe),
                      child: const Text('Retry'),
                    ),
                  ],
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              final bid = snapshot.data;
              if (bid == null ||
                  trip.status != 'accepted' ||
                  bid.id != trip.acceptedBidId ||
                  bid.tripId != trip.id ||
                  bid.driverId != trip.acceptedDriverId ||
                  bid.status != 'accepted') {
                return const Text(
                  'Your accepted bid details are not available.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TripCancellationButton(trip: trip, byDriver: true),
                  const Text(
                    'Your accepted bid',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  InfoLine(
                    icon: Icons.payments_outlined,
                    text: 'Price: ${bid.price}',
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
                  InfoLine(
                    icon: Icons.schedule_outlined,
                    text: 'Estimated trip duration: ${bid.estimatedTravelTime}',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
