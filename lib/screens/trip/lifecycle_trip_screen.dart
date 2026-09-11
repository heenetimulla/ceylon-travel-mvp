import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/trip_post.dart';
import '../../core/models/trip_lifecycle.dart';
import '../../core/models/bid.dart';
import '../../core/models/rating.dart';
import '../../core/services/trip_lifecycle_service.dart';
import '../../core/services/rating_service.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/trip_lifecycle_panel.dart';
import '../../core/widgets/trip_cancellation_button.dart';
import '../../core/widgets/reputation_summary.dart';
import '../../core/widgets/participant_profile_card.dart';
import '../rating/rating_screen.dart';
import '../support/support_screens.dart';
import '../chat/trip_chat_screen.dart';
import '../../core/models/trip_chat_message.dart';

class LifecycleTripScreen extends StatefulWidget {
  const LifecycleTripScreen({super.key, required this.tripId});
  final String tripId;
  @override
  State<LifecycleTripScreen> createState() => _LifecycleTripScreenState();
}
class _LifecycleTripScreenState extends State<LifecycleTripScreen> {
  late final _service = TripLifecycleService();
  late final _actor = _service.uid;
  StreamSubscription<TripPost>? _subscription;
  Timer? _timer;
  TripPost? _trip;
  String? _error;
  bool _busy = false;
  String? _bidId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _bid;
  Stream<Rating?>? _rating;
  @override
  void initState() {
    super.initState(); _subscribe();
    // Display only: Firestore snapshots deliver trusted backend transitions.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }
  void _subscribe() {
    _subscription?.cancel();
    _subscription = _service.watchTrip(widget.tripId).listen((trip) {
      if (!mounted) return;
      setState(() {
        _trip = trip; _error = null;
        if (trip.acceptedBidId != _bidId) {
          _bidId = trip.acceptedBidId;
          _bid = _bidId == null ? null : FirebaseFirestore.instance.collection('trip_posts').doc(trip.id).collection('bids').doc(_bidId).snapshots();
        }
        if (trip.status == 'completed' && _rating == null) _rating = RatingService().watchOwnRating(trip);
      });
    }, onError: (_) { if (mounted) setState(() => _error = 'This trip is unavailable. It may have reopened or your access may have changed.'); });
  }
  Future<void> _act(LifecycleAction action) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      switch (action) {
        case LifecycleAction.requestStart: await _service.requestStart(widget.tripId);
        case LifecycleAction.confirmStart: await _service.confirmStart(widget.tripId);
        case LifecycleAction.requestEnd: await _service.requestEnd(widget.tripId);
        case LifecycleAction.confirmEnd: await _service.confirmEnd(widget.tripId);
      }
      if (mounted && action == LifecycleAction.requestStart) {
        await showDialog<void>(context: context, builder: (context) => AlertDialog(
          title: const Text('Start request sent'),
          content: const SingleChildScrollView(child: Text('The person who posted this hire has been notified.\n\nThey can confirm the trip start, or the trip will automatically start in 3 minutes.\n\nYou may leave with the passenger and begin the journey.')),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update the trip yet. Check your connection. The server controls confirmation deadlines; automatic updates are handled by the server.');
    } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  void dispose() { _timer?.cancel(); _subscription?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return Scaffold(appBar: const AppPageAppBar(title: Text('Trip Details')),
      body: trip == null ? Center(child: _error == null ? const CircularProgressIndicator() : TextButton(onPressed: _subscribe, child: Text(_error!)))
      : ListView(padding: appPagePadding(context), children: [
        if (_error != null) AppInfoCard(children: [Text(_error!), TextButton(onPressed: _subscribe, child: const Text('Refresh Trip'))]),
        TripLifecyclePanel(trip: trip, uid: _actor, now: DateTime.now(), busy: _busy, onAction: _act),
        ParticipantProfileCard(trip: trip, actor: _actor),
        if (TripChatMessage.canRead(trip, _actor))
          OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TripChatScreen(tripPost: trip))),
            icon: const Icon(Icons.chat_bubble_outline),
            label: Text(TripChatMessage.canWrite(trip, _actor) ? 'Open Trip Chat' : 'View Chat History')),
        AppInfoCard(children: [AppRoute(pickup: trip.pickup, destination: trip.drop),
          const SizedBox(height: 16), Text(trip.dateTime), Text(trip.passengers), Text(trip.baggage),
          Text('Vehicle preference: ${trip.vehiclePreference}'), Text(trip.notes)]),
        AppInfoCard(children: [const AppSectionHeader('Posted by'), Text(trip.creatorName), Text(trip.creatorTypeLabel), ReputationSummary(uid: trip.creatorId, creator: true)]),
        if (_bid != null) StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: _bid, builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Accepted offer currently unavailable.');
          if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
          final bid = Bid.fromFirestore(snapshot.data!);
          return AppInfoCard(children: [const AppSectionHeader('Accepted driver'), Text(bid.driverName),
            Text('Price: ${bid.price}'), Text('Vehicle type: ${bid.vehicleType}'), Text('Vehicle: ${bid.vehicleDetails}'),
            Text('Vehicle number: ${bid.vehicleNumber}'), Text('Estimated trip duration: ${bid.estimatedTravelTime}'),
            ReputationSummary(uid: trip.acceptedDriverId)]);
        }),
        if (trip.canCancel && !_busy) TripCancellationButton(trip: trip, byDriver: _actor == trip.acceptedDriverId),
        if (trip.status == 'completed') ...[
          StreamBuilder<Rating?>(stream: _rating, builder: (context, snapshot) {
            if (snapshot.hasError) return const Text('Your rating status is unavailable. Reopen this trip to retry.');
            if (snapshot.connectionState == ConnectionState.waiting) return const Text('Checking your rating...');
            if (snapshot.data != null) return AppInfoCard(children: [Text('Your rating: ${snapshot.data!.stars}/5'), Text(snapshot.data!.comment)]);
            return AppInfoCard(children: [AppSectionHeader(_actor == trip.creatorId ? 'Rate your driver' : 'Rate the person who gave/created this hire'),
              FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RatingScreen(trip: trip, byCreator: _actor == trip.creatorId))), child: const Text('Write a Review'))]);
          }),
          OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupportFormScreen(trip: trip, byCreator: _actor == trip.creatorId))),
            icon: const Icon(Icons.report_outlined), label: const Text('Report / Complain about this trip')),
        ] else if (['start_requested', 'in_progress', 'end_requested'].contains(trip.status))
          OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportFormScreen())), child: const Text('Contact Us / Support')),
      ]),
    );
  }
}
