import 'package:flutter/material.dart';

import '../../core/models/bid.dart';
import '../../core/models/trip_post.dart';
import '../../core/widgets/bid_card.dart';
import '../../core/widgets/info_line.dart';

const List<Bid> _sampleBids = [
  Bid(
    id: 'bid-1',
    driverName: 'Nimal Perera',
    driverRating: 4.8,
    completedTrips: 126,
    cancellationRate: '0%',
    vehicleType: 'Van',
    price: 'LKR 42,000',
    estimatedTravelTime: '5 hours 30 minutes',
    message: 'I can pick you up on time and help with luggage.',
    status: 'submitted',
  ),
  Bid(
    id: 'bid-2',
    driverName: 'Saman Jayasinghe',
    driverRating: 4.6,
    completedTrips: 89,
    cancellationRate: '10%',
    vehicleType: 'SUV',
    price: 'LKR 45,500',
    estimatedTravelTime: '5 hours',
    message: 'Comfortable SUV with AC and space for bags.',
    status: 'submitted',
  ),
  Bid(
    id: 'bid-3',
    driverName: 'Ruwan Silva',
    driverRating: 4.9,
    completedTrips: 212,
    cancellationRate: '0%',
    vehicleType: 'Car',
    price: 'LKR 39,500',
    estimatedTravelTime: '6 hours',
    message: 'I know the Ella route well and can stop for photos.',
    status: 'submitted',
  ),
];

class TouristBidListScreen extends StatefulWidget {
  const TouristBidListScreen({super.key, required this.tripPost});

  final TripPost tripPost;

  @override
  State<TouristBidListScreen> createState() => _TouristBidListScreenState();
}

class _TouristBidListScreenState extends State<TouristBidListScreen> {
  late List<Bid> bids;
  String? acceptedBidId;

  @override
  void initState() {
    super.initState();
    bids = _sampleBids;
  }

  Future<void> _confirmAcceptBid(Bid selectedBid) async {
    final bool? shouldAccept = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Accept this driver bid?'),
          content: const Text(
            'After accepting one bid, other bids will be closed and this trip will move to pending trips.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Accept Bid'),
            ),
          ],
        );
      },
    );

    if (shouldAccept != true) return;
    if (!mounted) return;

    setState(() {
      acceptedBidId = selectedBid.id;
      bids = [
        for (final Bid bid in bids)
          bid.copyWith(
            status: bid.id == selectedBid.id ? 'accepted' : 'closed',
          ),
      ];
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bid accepted. Other bids are now closed.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TripPost tripPost = widget.tripPost;
    final bool hasAcceptedBid = acceptedBidId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Driver Bids')),
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
            const SizedBox(height: 12),
            const Card(
              color: Color(0xFFE0F2F1),
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, color: Color(0xFF0F766E)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Bids are private. Only you can see driver prices.',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (hasAcceptedBid) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Go to Pending Trip',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This trip is now waiting for the next MVP step.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Go to Pending Trip'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            for (final Bid bid in bids)
              BidCard(bid: bid, onAccept: () => _confirmAcceptBid(bid)),
          ],
        ),
      ),
    );
  }
}
