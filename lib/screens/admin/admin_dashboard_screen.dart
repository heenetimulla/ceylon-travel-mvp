import 'package:flutter/material.dart';
import '../../app/app_text_styles.dart';
import '../../core/models/admin_dashboard_stats.dart';
import '../../core/models/support_request.dart';
import '../../core/services/admin_service.dart';
import '../../core/widgets/admin_access_gate.dart';
import '../../core/widgets/admin_stat_card.dart';
import '../../core/widgets/app_components.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.service});
  final AdminService? service;
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final _service = widget.service ?? AdminService();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Admin Dashboard')),
    body: AdminAccessGate(service: _service,
      builder: (context, uid) => _Overview(service: _service)),
  );
}

/// One entry in the existing Account screen. The destination checks claims again.
class AdminDashboardEntry extends StatefulWidget {
  const AdminDashboardEntry({super.key, this.service});
  final AdminService? service;
  @override
  State<AdminDashboardEntry> createState() => _AdminDashboardEntryState();
}

class _AdminDashboardEntryState extends State<AdminDashboardEntry> {
  late final _service = widget.service ?? AdminService();
  @override
  Widget build(BuildContext context) => AdminAccessGate(service: _service, hideWhenDenied: true,
    builder: (context, uid) => Padding(padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(key: const Key('admin_dashboard_entry'),
        icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text('Admin Dashboard'),
        onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
          builder: (_) => AdminDashboardScreen(service: _service))))));
}

class _Overview extends StatefulWidget {
  const _Overview({required this.service});
  final AdminService service;
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  late Future<AdminDashboardData> _data = widget.service.loadDashboard();
  @override
  Widget build(BuildContext context) => FutureBuilder<AdminDashboardData>(future: _data,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading admin overview'));
      }
      if (snapshot.hasError || !snapshot.hasData) {
        return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(20), child: Text('Overview unavailable. Check your access and connection.')),
          TextButton(onPressed: () => setState(() => _data = widget.service.loadDashboard()), child: const Text('Retry overview')),
        ]));
      }
      final data = snapshot.data!;
      return ListView(padding: appPagePadding(context), children: [
        Row(children: [const Expanded(child: AppSectionHeader('Operations overview',
          subtitle: 'Current accounts, trips and support activity')),
          IconButton(tooltip: 'Refresh overview', onPressed: () => setState(() => _data = widget.service.loadDashboard()),
            icon: const Icon(Icons.refresh))]),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 850 ? 4 : constraints.maxWidth >= 500 ? 2 : 1;
          final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
          return Wrap(spacing: 12, runSpacing: 12, children: data.stats.cards.entries.map((entry) =>
            SizedBox(width: width, child: AdminStatCard(label: entry.key, value: entry.value))).toList());
        }),
        const AppSectionHeader('Recent support requests', spacious: true, subtitle: 'Latest 5 requests · Overview only'),
        if (data.recentSupport.isEmpty) const AppEmptyState(title: 'No support requests yet',
          message: 'New requests will appear here.', icon: Icons.support_agent_outlined),
        ...data.recentSupport.map((request) => _SupportPreview(request: request)),
      ]);
    });
}

class _SupportPreview extends StatelessWidget {
  const _SupportPreview({required this.request});
  final SupportRequest request;
  String _date(BuildContext context, DateTime? value) {
    if (value == null) return 'Not available';
    final local = value.toLocal();
    final format = MaterialLocalizations.of(context);
    return '${format.formatMediumDate(local)} ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(request.supportReference, style: AppTextStyles.cardTitle),
      const SizedBox(height: 8),
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(supportCategories[request.category] ?? request.category, style: AppTextStyles.body),
        AppStatusChip(request.status),
      ]),
      const SizedBox(height: 12),
      Text('User ID: ${request.userId}', style: AppTextStyles.secondary),
      Text('Contact: ${request.contactNumber}', style: AppTextStyles.secondary),
      Text('Created: ${_date(context, request.createdAt)}', style: AppTextStyles.caption),
      Text('Last message: ${_date(context, request.lastMessageAt)}', style: AppTextStyles.caption),
    ])));
}
