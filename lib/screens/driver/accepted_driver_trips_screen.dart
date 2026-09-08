import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/services/trip_post_service.dart';
import '../../core/widgets/trip_post_card.dart';
import 'accepted_driver_trip_screen.dart';

class AcceptedDriverTripsScreen extends StatefulWidget {
  const AcceptedDriverTripsScreen({super.key, this.watchTrips});

  final Stream<List<TripPost>> Function()? watchTrips;

  @override
  State<AcceptedDriverTripsScreen> createState() =>
      _AcceptedDriverTripsScreenState();
}

class _AcceptedDriverTripsScreenState extends State<AcceptedDriverTripsScreen> {
  late Stream<List<TripPost>> _trips;

  void _subscribe() {
    _trips =
        widget.watchTrips?.call() ??
        TripPostService().watchAcceptedDriverTrips();
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant AcceptedDriverTripsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.watchTrips != widget.watchTrips) {
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My accepted trips')),
      body: SafeArea(
        child: StreamBuilder<List<TripPost>>(
          key: ObjectKey(_trips),
          stream: _trips,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        error is TripPostServiceException
                            ? error.message
                            : 'Could not load your accepted trips. Please try again.',
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => setState(_subscribe),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(height: 12),
                    Text('Loading your accepted trips...'),
                  ],
                ),
              );
            }
            final trips = snapshot.data!;
            if (trips.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No accepted trips yet.\nTrips will appear here when your bid is accepted.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(18),
              itemCount: trips.length,
              itemBuilder: (context, index) {
                final trip = trips[index];
                return TripPostCard(
                  key: ValueKey(trip.id),
                  tripPost: trip,
                  onViewDetails: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AcceptedDriverTripScreen(tripPost: trip),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
