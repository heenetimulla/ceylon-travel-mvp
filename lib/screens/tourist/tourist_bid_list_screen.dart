import '../trip/lifecycle_trip_screen.dart';
import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../../core/models/bid.dart';
import '../../core/models/trip_post.dart';
import '../../core/services/bid_service.dart';
import '../../core/widgets/bid_card.dart';
import '../../core/widgets/info_line.dart';
import '../../core/widgets/trip_cancellation_button.dart';

class TouristBidListScreen extends StatefulWidget {
  const TouristBidListScreen({super.key, required this.tripPost});

  final TripPost tripPost;

  @override
  State<TouristBidListScreen> createState() => _TouristBidListScreenState();
}

class _TouristBidListScreenState extends State<TouristBidListScreen> {
  final BidService _bidService = BidService();
  late Stream<List<Bid>> _bidsStream;
  late Stream<TripPost> _tripStream;
  bool _isAccepting = false;
  String? _savingBidId;

  @override
  void initState() {
    super.initState();
    _bidsStream = _bidService.watchCreatorBids(widget.tripPost);
    _tripStream = _bidService.watchCreatorTrip(widget.tripPost);
  }

  @override
  void didUpdateWidget(covariant TouristBidListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripPost.id != widget.tripPost.id ||
        oldWidget.tripPost.creatorId != widget.tripPost.creatorId) {
      _bidsStream = _bidService.watchCreatorBids(widget.tripPost);
      _tripStream = _bidService.watchCreatorTrip(widget.tripPost);
    }
  }

  void _retry() {
    setState(() {
      _bidsStream = _bidService.watchCreatorBids(widget.tripPost);
      _tripStream = _bidService.watchCreatorTrip(widget.tripPost);
    });
  }

  Future<void> _confirmAcceptBid(TripPost trip, Bid bid) async {
    if (_isAccepting) return;
    setState(() => _isAccepting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Accept this driver bid?'),
          content: const Text(
            'After accepting this bid, bidding will close for this trip.',
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
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _savingBidId = bid.id);
      await _bidService.acceptBid(tripPost: trip, bidId: bid.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bid accepted successfully.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is BidServiceException
                  ? error.message
                  : 'Could not accept this bid. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAccepting = false;
          _savingBidId = null;
        });
      }
    }
  }

  Widget _acceptedSummary(Bid bid) {
    // TODO: Add contact retrieval only through secure accepted-trip sharing.
    // Do not read another user's private profile or expose their phone here.
    return Card(
      color: AppColors.softBlue,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bid accepted', style: AppTextStyles.section),
            const SizedBox(height: 12),
            Text('Driver: ${bid.driverName}'),
            Text('Price: ${bid.price}'),
            Text('Vehicle type: ${bid.vehicleType}'),
            Text('Vehicle details: ${bid.vehicleDetails}'),
            Text(
              'Vehicle number: ${bid.vehicleNumber.isEmpty ? 'Not provided' : bid.vehicleNumber}',
            ),
            Text('Estimated trip duration: ${bid.estimatedTravelTime}'),
          ],
        ),
      ),
    );
  }

  Widget _buildBids(TripPost trip) {
    return StreamBuilder<List<Bid>>(
      key: ObjectKey(_bidsStream),
      stream: _bidsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final error = snapshot.error;
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  error is BidServiceException
                      ? error.message
                      : 'Could not load bids. Please try again.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(height: 12),
                Text('Loading driver bids...'),
              ],
            ),
          );
        }
        final bids = snapshot.data!;
        if (bids.isEmpty) {
          return const AppEmptyState(
            title: 'No driver bids yet.',
            message: 'New bids will appear here automatically.',
            icon: Icons.local_offer_outlined,
          );
        }
        return Column(
          children: [
            if (TripPost.assignedStatuses.contains(trip.status))
              for (final bid in bids)
                if (bid.id == trip.acceptedBidId) _acceptedSummary(bid),
            for (final bid in bids)
              BidCard(
                key: ValueKey(bid.id),
                bid: bid,
                effectiveStatus: bid.effectiveStatusFor(trip),
                isSaving: _savingBidId == bid.id,
                onAccept:
                    !_isAccepting &&
                        trip.status == 'open' &&
                        trip.acceptedBidId == null &&
                        trip.acceptedDriverId == null &&
                        bid.effectiveStatusFor(trip) == 'submitted'
                    ? () => _confirmAcceptBid(trip, bid)
                    : null,
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppPageAppBar(title: const Text('Driver Bids')),
      body: StreamBuilder<TripPost>(
        key: ObjectKey(_tripStream),
        stream: _tripStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error is BidServiceException
                        ? error.message
                        : 'Could not load this trip.',
                    textAlign: TextAlign.center,
                  ),
                  TextButton(onPressed: _retry, child: const Text('Retry')),
                ],
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }
          final tripPost = snapshot.data!;
          return SafeArea(
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
                        const Text(
                          'Trip summary',
                          style: AppTextStyles.section,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${tripPost.pickup} -> ${tripPost.drop}',
                          style: AppTextStyles.cardTitle,
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
                  color: AppColors.softBlue,
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline, color: AppColors.ocean),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bids are private. Only you can see driver prices.',
                            style: AppTextStyles.cardTitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (['open', 'accepted'].contains(tripPost.status) &&
                    !_isAccepting)
                  TripCancellationButton(trip: tripPost, byDriver: false),
                if (tripPost.status == 'cancelled')
                  const Text('This trip has been cancelled.'),
                if (TripPost.assignedStatuses.contains(tripPost.status))
                  FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LifecycleTripScreen(tripId: tripPost.id))), child: const Text('Manage Trip / View Status')),
                _buildBids(tripPost),
              ],
            ),
          );
        },
      ),
    );
  }
}
