import 'package:flutter/material.dart';
import '../../app/app_text_styles.dart';
import '../../core/models/admin_support_data.dart';
import '../../core/models/support_request.dart';
import '../../core/services/admin_support_service.dart';
import '../../core/widgets/admin_support_components.dart';
import '../../core/widgets/app_components.dart';
import 'admin_support_detail_screen.dart';

class AdminSupportInboxScreen extends StatefulWidget {
  const AdminSupportInboxScreen({super.key, this.service});
  final AdminSupportService? service;
  @override
  State<AdminSupportInboxScreen> createState() => _AdminSupportInboxScreenState();
}
class _AdminSupportInboxScreenState extends State<AdminSupportInboxScreen> {
  late final _service = widget.service ?? AdminSupportService();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Support & Complaints')),
    body: AdminSupportGate(service: _service, builder: (context, uid) => _Inbox(service: _service)),
  );
}

/// Separate Account entry gives support-only staff access without granting the
/// primary-admin dashboard, user browser or aggregate reads.
class AdminSupportEntry extends StatefulWidget {
  const AdminSupportEntry({super.key, this.service});
  final AdminSupportService? service;
  @override
  State<AdminSupportEntry> createState() => _AdminSupportEntryState();
}
class _AdminSupportEntryState extends State<AdminSupportEntry> {
  late final _service = widget.service ?? AdminSupportService();
  @override
  Widget build(BuildContext context) => AdminSupportGate(service: _service, hideWhenDenied: true,
    builder: (context, uid) => Padding(padding: const EdgeInsets.only(top: 12), child: OutlinedButton.icon(
      key: const Key('support_staff_entry'), icon: const Icon(Icons.support_agent),
      label: const Text('Support & Complaints'), onPressed: () => Navigator.push(context,
        MaterialPageRoute<void>(builder: (_) => AdminSupportInboxScreen(service: _service))))));
}

class _Inbox extends StatefulWidget {
  const _Inbox({required this.service});
  final AdminSupportService service;
  @override
  State<_Inbox> createState() => _InboxState();
}
class _InboxState extends State<_Inbox> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _requests = <SupportRequest>[];
  SupportInboxFilter _filter = SupportInboxFilter.all;
  SupportCursor? _next;
  bool _loading = true, _failed = false, _loaded = false;
  int _generation = 0;
  @override
  void initState() { super.initState(); _load(reset: true); }
  @override
  void dispose() { _generation++; _search.dispose(); _scroll.dispose(); super.dispose(); }

  Future<void> _load({bool reset = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true; _failed = false;
      if (reset) { _requests.clear(); _next = null; _loaded = false; }
    });
    if (reset && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      final page = await widget.service.loadRequests(filter: _filter, cursor: _next);
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _requests.map((r) => r.id).toSet();
        _requests.addAll(page.items.where((r) => ids.add(r.id)));
        _next = page.next; _loaded = true; _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _requests.where((request) => supportMatchesSearch(request, _search.text)).toList();
    return CustomScrollView(controller: _scroll, slivers: [
      SliverPadding(padding: appPagePadding(context).copyWith(bottom: 0), sliver: SliverToBoxAdapter(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: AppSectionHeader('Support inbox', subtitle: 'Review requests and help customers')),
            IconButton(tooltip: 'Refresh inbox', onPressed: _loading ? null : () => _load(reset: true),
              icon: const Icon(Icons.refresh)),
          ]),
          TextField(key: const Key('support_inbox_search'), controller: _search,
            onChanged: (_) => setState(() {}), decoration: InputDecoration(
              labelText: 'Search loaded requests', hintText: 'Reference, name, contact or category',
              prefixIcon: const Icon(Icons.search), border: const OutlineInputBorder(),
              suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear search',
                onPressed: () => setState(_search.clear), icon: const Icon(Icons.close)))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: SupportInboxFilter.values.map((filter) => ChoiceChip(
            key: ValueKey('support_filter_${filter.name}'), label: Text(filter.label), selected: _filter == filter,
            onSelected: (_) { if (_filter != filter) { _filter = filter; _load(reset: true); } },
          )).toList()),
          const SizedBox(height: 12),
          Text('${visible.length} matching · ${_requests.length} loaded', style: AppTextStyles.secondary),
          const Text('Newest requests first. Search covers loaded requests in this filter. '
            'Load more to search further; refresh for updates.', style: AppTextStyles.caption),
          if (_loaded && !_loading && !_failed && visible.isEmpty) AppEmptyState(
            title: _search.text.trim().isEmpty ? 'No support requests' : 'No matching loaded requests',
            message: _next == null ? 'Try another filter or search.' : 'Load more requests to continue searching.',
            icon: Icons.support_agent),
        ]))),
      SliverPadding(padding: appPagePadding(context).copyWith(top: 8, bottom: 0), sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final request = visible[index];
          return Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.supportReference, style: AppTextStyles.cardTitle),
              Text(supportCategoryLabel(request)),
              AppStatusChip(supportStatuses[request.status] ?? request.status),
              const SizedBox(height: 8),
              Text('Requester: ${request.userName}'), Text('User ID: ${request.userId}'),
              Text('Contact: ${request.contactNumber}'),
              if (request.tripReference != null) Text('Trip: ${request.tripReference}'),
              Text('Created: ${adminSupportDate(context, request.createdAt)}'),
              Text('Updated: ${adminSupportDate(context, request.updatedAt)}'),
              Text('Last message: ${adminSupportDate(context, request.lastMessageAt)}'),
              TextButton(onPressed: () async {
                await Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                  AdminSupportDetailScreen(requestId: request.id, service: widget.service)));
                if (mounted) _load(reset: true);
              }, child: const Text('Open request')),
            ])));
        }, childCount: visible.length))),
      SliverPadding(padding: appPagePadding(context), sliver: SliverToBoxAdapter(child: Column(children: [
        if (_loading) const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading support requests')),
        if (_failed) ...[
          const Text('Support inbox unavailable. Check your access and connection.'),
          TextButton(onPressed: () => _load(reset: !_loaded), child: const Text('Retry inbox')),
        ],
        if (!_loading && !_failed && _next != null)
          OutlinedButton(onPressed: () => _load(), child: const Text('Load more requests')),
        if (_loaded && !_loading && !_failed && _next == null && _requests.isNotEmpty)
          const Text('All requests in this filter loaded'),
      ]))),
    ]);
  }
}
