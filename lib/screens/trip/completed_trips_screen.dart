import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/models/trip_post.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/trip_post_card.dart';
import 'lifecycle_trip_screen.dart';

class CompletedTripsScreen extends StatefulWidget {
  const CompletedTripsScreen({super.key});
  @override
  State<CompletedTripsScreen> createState() => _CompletedTripsScreenState();
}
class _CompletedTripsScreenState extends State<CompletedTripsScreen> {
  late final String _uid = FirebaseAuth.instance.currentUser!.uid;
  late final _created = FirebaseFirestore.instance.collection('trip_posts').where('creatorId', isEqualTo: _uid).where('status', isEqualTo: 'completed').snapshots();
  late final _performed = FirebaseFirestore.instance.collection('trip_posts').where('acceptedDriverId', isEqualTo: _uid).where('status', isEqualTo: 'completed').snapshots();
  Widget _list(String title, Stream<QuerySnapshot<Map<String, dynamic>>> stream) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    AppSectionHeader(title),
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: stream, builder: (context, snapshot) {
      if (snapshot.hasError) return const Text('Could not load completed trips. Please reopen this page to retry.');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final trips = snapshot.data!.docs.map(TripPost.fromFirestore).toList()
        ..sort((a,b) => (b.endedAt ?? b.scheduledAt).compareTo(a.endedAt ?? a.scheduledAt));
      if (trips.isEmpty) return const AppEmptyState(title: 'No completed trips yet', message: 'Your completed journeys will appear here.');
      return Column(children: [for (final trip in trips) TripPostCard(tripPost: trip,
        onViewDetails: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LifecycleTripScreen(tripId: trip.id))))]);
    }),
  ]);
  @override
  Widget build(BuildContext context) => Scaffold(appBar: const AppPageAppBar(title: Text('Completed Trips')),
    body: ListView(padding: appPagePadding(context), children: [
      _list('Completed hires you created', _created), _list('Completed trips you drove', _performed),
    ]),
  );
}
