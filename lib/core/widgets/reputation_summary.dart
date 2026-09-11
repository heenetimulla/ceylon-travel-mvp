import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import '../../app/app_text_styles.dart';
import '../models/user_reputation.dart';

class ReputationSummary extends StatelessWidget {
  const ReputationSummary({super.key, this.uid, this.reputation, this.fallback, this.creator = false});
  final String? uid;
  final UserReputation? reputation;
  final UserReputation? fallback;
  final bool creator;
  @override
  Widget build(BuildContext context) {
    if (reputation != null) return _values(reputation!);
    // Keep public/demo widgets usable without initializing Firebase.
    if (uid == null || Firebase.apps.isEmpty || FirebaseAuth.instance.currentUser == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('user_reputation').doc(uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Reputation currently unavailable', style: AppTextStyles.caption);
        if (!snapshot.hasData) return const Text('Loading reputation...', style: AppTextStyles.caption);
        if (!snapshot.data!.exists) return fallback != null ? _values(fallback!) : const Text('Reputation not yet available', style: AppTextStyles.caption);
        return _values(UserReputation.fromMap(snapshot.data!.data()!));
      },
    );
  }
  Widget _values(UserReputation rep) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(spacing: 16, runSpacing: 6, children: [
      Text('${creator ? 'Completed hires' : 'Completed trips'}: ${rep.completedTripsCount}', style: AppTextStyles.secondary),
      Text('Cancellations: ${rep.cancellationCount ?? 'Not available'}', style: AppTextStyles.secondary),
      Text('Cancellation rate: ${rep.cancellationRate == null ? 'Not available' : '${rep.cancellationRate!.toStringAsFixed(0)}%'}', style: AppTextStyles.secondary),
      Text('Rating: ${rep.averageRating.toStringAsFixed(1)} (${rep.ratingsCount} reviews)', style: AppTextStyles.secondary),
    ]),
  );
}
