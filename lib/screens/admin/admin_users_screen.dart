import 'package:flutter/material.dart';
import '../../app/app_text_styles.dart';
import '../../core/models/admin_user_summary.dart';
import '../../core/services/admin_service.dart';
import '../../core/widgets/admin_access_gate.dart';
import '../../core/widgets/app_components.dart';
import 'admin_user_detail_screen.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.service});
  final AdminService? service;
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late final _service = widget.service ?? AdminService();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Users & Drivers')),
    body: AdminAccessGate(service: _service,
      builder: (context, uid) => _UserList(service: _service)),
  );
}

class _UserList extends StatefulWidget {
  const _UserList({required this.service});
  final AdminService service;
  @override
  State<_UserList> createState() => _UserListState();
}

class _UserListState extends State<_UserList> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _users = <AdminUserSummary>[];
  AdminUserFilter _filter = AdminUserFilter.all;
  String? _nextUid;
  bool _loading = true, _failed = false, _loaded = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) {
        _users.clear();
        _nextUid = null;
        _loaded = false;
      }
    });
    if (reset && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      final page = await widget.service.loadUsers(filter: _filter, afterUid: _nextUid);
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _users.map((user) => user.uid).toSet();
        _users.addAll(page.users.where((user) => ids.add(user.uid)));
        _nextUid = page.nextUid;
        _loaded = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _users.where((user) => user.matchesSearch(_search.text)).toList();
    return CustomScrollView(controller: _scroll, slivers: [
      SliverPadding(padding: appPagePadding(context).copyWith(bottom: 0),
        sliver: SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: AppSectionHeader('Registered accounts',
              subtitle: 'Read-only account and driver information')),
            IconButton(tooltip: 'Refresh accounts',
              onPressed: _loading ? null : () => _load(reset: true), icon: const Icon(Icons.refresh)),
          ]),
          TextField(controller: _search, onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Search loaded accounts',
              hintText: 'Name, email or phone', prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear search',
                onPressed: () => setState(_search.clear), icon: const Icon(Icons.close)),
              border: const OutlineInputBorder())),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: AdminUserFilter.values.map((filter) => ChoiceChip(
            key: ValueKey('filter_${filter.name}'), label: Text(filter.label), selected: _filter == filter,
            onSelected: (_) {
              if (_filter == filter) return;
              _filter = filter;
              _load(reset: true);
            })).toList()),
          const SizedBox(height: 12),
          const Text('Accounts are ordered by account ID, including older profiles without dates. '
            'Search covers loaded accounts in the selected filter. Load more to search further.',
            style: AppTextStyles.caption),
          const SizedBox(height: 8),
          Text('${visible.length} matching · ${_users.length} loaded', style: AppTextStyles.secondary),
          const SizedBox(height: 12),
          if (_loaded && !_loading && !_failed && visible.isEmpty) AppEmptyState(
            title: _search.text.trim().isNotEmpty ? 'No matching loaded accounts' : 'No accounts found',
            message: _nextUid != null ? 'Load more accounts to continue searching.'
              : 'Try another search or account filter.', icon: Icons.people_outline),
        ]))),
      SliverPadding(padding: appPagePadding(context).copyWith(top: 0, bottom: 0),
        sliver: SliverList(delegate: SliverChildBuilderDelegate((context, index) {
          final user = visible[index];
          return _AccountCard(user: user, onOpen: () => Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => AdminUserDetailScreen(uid: user.uid, service: widget.service))));
        }, childCount: visible.length))),
      SliverPadding(padding: appPagePadding(context), sliver: SliverToBoxAdapter(
        child: Column(children: [
          if (_loading) const Padding(padding: EdgeInsets.all(20),
            child: CircularProgressIndicator(semanticsLabel: 'Loading accounts')),
          if (_failed) ...[
            const Text('Accounts unavailable. Check your access and connection.', textAlign: TextAlign.center),
            TextButton(onPressed: () => _load(reset: !_loaded), child: const Text('Retry accounts')),
          ],
          if (!_loading && !_failed && _nextUid != null)
            OutlinedButton.icon(onPressed: () => _load(), icon: const Icon(Icons.expand_more),
              label: const Text('Load more accounts')),
          if (_loaded && !_loading && !_failed && _nextUid == null && _users.isNotEmpty)
            const Text('All accounts in this filter loaded', style: AppTextStyles.caption),
        ]))),
    ]);
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.user, required this.onOpen});
  final AdminUserSummary user;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(key: ValueKey('account_${user.uid}'),
    child: Padding(padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(user.displayName, style: AppTextStyles.cardTitle),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(user.accountTypeLabel, style: AppTextStyles.body),
          AppStatusChip(user.statusLabel),
        ]),
        const SizedBox(height: 12),
        Text('Phone: ${user.phoneNumber ?? 'Not available'}'),
        Text('Completed trips: ${user.completedTripsCount ?? 'Not available'}'),
        Text('Cancelled trips: ${user.cancelledTripsCount ?? 'Not available'}'),
        Text('Cancellation rate: ${user.cancellationRateLabel}'),
        Text('Average rating: ${user.averageRatingLabel} · Ratings: ${user.ratingsCount ?? 'Not available'}'),
        if (user.registrationStatus != null) Text('Application: ${user.registrationStatus!.replaceAll('_', ' ')}'),
        if (user.verificationStatus != null) Text('Verification: ${user.verificationStatus!.replaceAll('_', ' ')}'),
        const SizedBox(height: 8),
        TextButton.icon(onPressed: onOpen, icon: const Icon(Icons.person_outline),
          label: const Text('View account')),
      ])));
}
