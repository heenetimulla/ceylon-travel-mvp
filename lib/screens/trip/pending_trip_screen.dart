import 'package:flutter/material.dart';
import '../../core/models/trip_post.dart';
import '../../core/models/bid.dart';
import 'lifecycle_trip_screen.dart';

class PendingTripScreen extends StatelessWidget {
  const PendingTripScreen({super.key, required this.tripPost, required this.acceptedBid});
  final TripPost tripPost;
  final Bid acceptedBid;
  @override
  Widget build(BuildContext context) => LifecycleTripScreen(tripId: tripPost.id);
}
