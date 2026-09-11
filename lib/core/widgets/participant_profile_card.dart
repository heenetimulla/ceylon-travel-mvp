import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../app/app_text_styles.dart';
import '../models/public_profile.dart';
import '../models/trip_post.dart';
import 'app_components.dart';
import 'profile_avatar.dart';
import 'reputation_summary.dart';

class ParticipantProfileCard extends StatefulWidget {
  const ParticipantProfileCard({super.key, required this.trip, required this.actor,
    this.profileStream, this.reviewsStream});
  final TripPost trip;
  final String actor;
  final Stream<PublicProfile?>? profileStream;
  final Stream<List<Map<String, dynamic>>>? reviewsStream;
  @override
  State<ParticipantProfileCard> createState() => _ParticipantProfileCardState();
}
class _ParticipantProfileCardState extends State<ParticipantProfileCard> {
  Stream<PublicProfile?>? _profile;
  void _subscribe() {
    final uid = PublicProfile.otherParticipant(widget.trip, widget.actor);
    _profile = uid == null ? null : widget.profileStream ?? FirebaseFirestore.instance
      .collection('user_public_profiles').doc(uid).snapshots()
      .map((doc) => doc.exists ? PublicProfile.fromMap(doc.data()!) : null);
  }
  @override
  void initState() { super.initState(); _subscribe(); }
  @override
  void didUpdateWidget(covariant ParticipantProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (PublicProfile.otherParticipant(oldWidget.trip, oldWidget.actor) != PublicProfile.otherParticipant(widget.trip, widget.actor) ||
        oldWidget.profileStream != widget.profileStream) {
      _subscribe();
    }
  }
  @override
  Widget build(BuildContext context) {
    final uid = PublicProfile.otherParticipant(widget.trip, widget.actor);
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<PublicProfile?>(
      key: ValueKey(uid), stream: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final creator = widget.actor == widget.trip.acceptedDriverId;
        return AppInfoCard(children: [
          AppSectionHeader(creator ? 'Hire creator profile' : 'Accepted driver profile'),
          if (snapshot.hasError) const Text('Profile currently unavailable')
          else if (profile == null) Text(snapshot.connectionState == ConnectionState.waiting ? 'Loading profile...' : 'Profile not yet available')
          else ...[
            Row(children: [ProfileAvatar(fullName: profile.fullName, profilePhotoPath: profile.profilePhotoPath),
              const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(profile.fullName.isEmpty ? 'Name not available' : profile.fullName, style: AppTextStyles.section),
                Text(profile.verificationStatus == 'verified' ? 'Verified' : 'Not Verified'),
              ]))]),
            if (profile.reputation != null) ReputationSummary(reputation: profile.reputation, creator: creator)
            else const Text('Reputation not yet available'),
            if ((profile.reputation?.ratingsCount ?? 0) > 0)
              TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ParticipantReviewsScreen(
                uid: uid, reviewsStream: widget.reviewsStream))), child: const Text('View Reviews')),
          ],
        ]);
      });
  }
}

class ParticipantReviewsScreen extends StatefulWidget {
  const ParticipantReviewsScreen({super.key, required this.uid, this.reviewsStream});
  final String uid;
  final Stream<List<Map<String, dynamic>>>? reviewsStream;
  @override
  State<ParticipantReviewsScreen> createState() => _ParticipantReviewsScreenState();
}
class _ParticipantReviewsScreenState extends State<ParticipantReviewsScreen> {
  late final _reviews = widget.reviewsStream ?? FirebaseFirestore.instance
    .collection('user_public_profiles').doc(widget.uid).collection('reviews')
    .orderBy('createdAt', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  @override
  Widget build(BuildContext context) => Scaffold(appBar: const AppPageAppBar(title: Text('Reviews')),
    body: StreamBuilder<List<Map<String, dynamic>>>(stream: _reviews, builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Reviews currently unavailable'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      if (snapshot.data!.isEmpty) return const AppEmptyState(title: 'No reviews available', message: 'Written reviews will appear here when available.');
      return ListView(padding: appPagePadding(context), children: [for (final review in snapshot.data!)
        AppInfoCard(children: [Text('${review['stars']}/5', style: AppTextStyles.section),
          Text(review['comment'] as String),
          if (review['createdAt'] is Timestamp) Text(MaterialLocalizations.of(context).formatMediumDate((review['createdAt'] as Timestamp).toDate().toLocal())),
          if (review['tripReference'] is String) Text('Trip: ${review['tripReference']}'),
        ])]);
    }));
}
