import 'package:flutter/material.dart';
import '../../app/app_text_styles.dart';
import '../../core/models/admin_user_summary.dart';
import '../../core/services/admin_service.dart';
import '../../core/widgets/admin_access_gate.dart';
import '../../core/widgets/app_components.dart';

class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.uid, this.service});
  final String uid;
  final AdminService? service;
  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late final _service = widget.service ?? AdminService();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Account details')),
    body: AdminAccessGate(service: _service, builder: (context, adminUid) =>
      _AccountDetails(key: ValueKey(widget.uid), uid: widget.uid, service: _service)),
  );
}

class _AccountDetails extends StatefulWidget {
  const _AccountDetails({super.key, required this.uid, required this.service});
  final String uid;
  final AdminService service;
  @override
  State<_AccountDetails> createState() => _AccountDetailsState();
}

class _AccountDetailsState extends State<_AccountDetails> {
  late Future<AdminUserSummary?> _data = widget.service.loadUser(widget.uid);

  void _reload() {
    if (!mounted) return;
    final next = widget.service.loadUser(widget.uid);
    setState(() {
      _data = next;
    });
    // FutureBuilder ignores completions from a replaced future or disposed state.
  }

  String _date(BuildContext context, DateTime? value) {
    if (value == null) return 'Not available';
    final local = value.toLocal();
    final format = MaterialLocalizations.of(context);
    return '${format.formatFullDate(local)} ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AdminUserSummary?>(future: _data,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading account details'));
      }
      if (snapshot.hasError) {
        return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const Text('Account unavailable. Check your access and connection.', textAlign: TextAlign.center),
            TextButton(onPressed: _reload,
              child: const Text('Retry account')),
          ])));
      }
      final user = snapshot.data;
      if (user == null) {
        return const Center(child: AppEmptyState(title: 'Account not found',
          message: 'This account profile is no longer available.', icon: Icons.person_off_outlined));
      }
      final fields = <String, Object?>{
        'Full name': user.fullName,
        'UID': user.uid,
        'Account type': user.accountTypeLabel,
        'Email': user.email,
        'Phone number': user.phoneNumber,
        'City': user.city,
        'Status': user.status,
        'Created': _date(context, user.createdAt),
        'Updated': _date(context, user.updatedAt),
        'Completed trips': user.completedTripsCount,
        'Cancelled trips': user.cancelledTripsCount,
        'Cancellation rate': user.cancellationRateLabel,
        'Average rating': user.averageRatingLabel,
        'Rating count': user.ratingsCount,
        'Verification status': user.verificationStatus?.replaceAll('_', ' '),
        'Profile photo status': user.profilePhotoPath == null ? 'No path provided' : 'Path provided (image not loaded)',
        'Profile photo path': user.profilePhotoPath,
      };
      return ListView(padding: appPagePadding(context), children: [
        Row(children: [
          Expanded(child: AppSectionHeader(user.displayName, subtitle: 'Read-only account details')),
          IconButton(tooltip: 'Refresh account',
            onPressed: _reload,
            icon: const Icon(Icons.refresh)),
        ]),
        AppInfoCard(children: fields.entries.map((entry) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.key, style: AppTextStyles.caption),
              const SizedBox(height: 4),
              SelectableText('${entry.value ?? 'Not available'}', style: AppTextStyles.body),
            ]))).toList()),
      ]);
    });
}
