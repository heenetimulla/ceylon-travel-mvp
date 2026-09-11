import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../core/services/support_service.dart';
import '../../core/models/user_reputation.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/reputation_summary.dart';
import '../support/support_screens.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}
class _AccountScreenState extends State<AccountScreen> {
  late final _profile = SupportService().loadProfile();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: const AppPageAppBar(title: Text('Account & Support')),
    body: ListView(padding: appPagePadding(context), children: [
      FutureBuilder<Map<String, dynamic>>(future: _profile, builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Profile unavailable. Please reopen this screen to retry.');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        return AppInfoCard(children: [AppSectionHeader(data['fullName'] as String), Text(data['accountType'] as String),
          Text(data['phoneNumber'] as String? ?? ''),
          ReputationSummary(uid: FirebaseAuth.instance.currentUser!.uid, fallback: UserReputation.fromMap({...data, 'cancellationCount': null, 'cancellationRate': null}), creator: data['accountType'] != 'driver'),
        ]);
      }),
      FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportFormScreen())), child: const Text('Contact Us / Support')),
      const SizedBox(height: 12),
      OutlinedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportRequestsScreen())), child: const Text('My Support Requests')),
    ]),
  );
}
