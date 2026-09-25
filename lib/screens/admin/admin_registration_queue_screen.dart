import 'package:flutter/material.dart';
import '../../core/models/account_attention.dart';
import '../../core/services/admin_registration_queue_service.dart';
import '../../core/services/admin_service.dart';
import '../../core/widgets/admin_access_gate.dart';
import '../../core/widgets/app_components.dart';
import 'admin_user_detail_screen.dart';

class AdminRegistrationQueueScreen extends StatelessWidget {
  const AdminRegistrationQueueScreen({super.key, required this.service, this.initialFilter = RegistrationQueueFilter.all});
  final AdminRegistrationQueueService service;
  final RegistrationQueueFilter initialFilter;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: const AppPageAppBar(title: Text('Pending Registrations')),
    body: AdminAccessGate(service: service.admin, builder: (_, uid) => _Queue(key: ValueKey(uid), service: service, initial: initialFilter)));
}
class _Queue extends StatefulWidget {
  const _Queue({super.key, required this.service, required this.initial});
  final AdminRegistrationQueueService service;
  final RegistrationQueueFilter initial;
  @override
  State<_Queue> createState() => _QueueState();
}
class _QueueState extends State<_Queue> {
  late RegistrationQueueFilter _filter = widget.initial;
  final _rows = <RegistrationQueueRow>[];
  String? _cursor;
  bool _busy = true, _error = false;
  int _generation = 0;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _generation++; super.dispose(); }
  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() { _busy = true; _error = false; if (!more) { _rows.clear(); _cursor = null; } });
    try {
      final page = await widget.service.page(_filter, afterUid: _cursor);
      if (!mounted || generation != _generation) { return; }
      setState(() { final ids = _rows.map((r) => r.user.uid).toSet(); _rows.addAll(page.rows.where((r) => ids.add(r.user.uid))); _cursor = page.nextUid; });
    } catch (_) { if (mounted && generation == _generation) { setState(() => _error = true); } }
    finally { if (mounted && generation == _generation) { setState(() => _busy = false); } }
  }
  @override
  Widget build(BuildContext context) => ListView(padding: appPagePadding(context), children: [
    Wrap(spacing: 8, children: [for (final filter in RegistrationQueueFilter.values) ChoiceChip(label: Text(filter.label),
      selected: _filter == filter, onSelected: (_) { _filter = filter; _load(); })]),
    const Text('Identity queues include rejected applications eligible for follow-up. Payment & Activation includes pending or rejected payments and membership activation waiting for review.'),
    TextButton(onPressed: _busy ? null : () => _load(), child: const Text('Refresh registrations')),
    for (final row in _rows) Card(child: ListTile(title: Text(row.user.displayName),
      subtitle: Text('${row.user.accountTypeLabel} · ${row.user.statusLabel}\n'
        'Registration: ${row.user.registrationStatus}\nRevision: ${row.revision ?? 'Not available'}\n'
        'Submitted: ${row.submittedAt?.toLocal() ?? 'Not available'}\nPhone: ${row.user.phoneNumber ?? 'Not available'}'),
      trailing: const Icon(Icons.chevron_right), onTap: () async {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AdminUserDetailScreen(uid: row.user.uid, service: widget.service.admin,
          paymentFocus: _filter == RegistrationQueueFilter.payment)));
        if (mounted) { _load(); }
      })),
    if (_busy) const Center(child: CircularProgressIndicator()),
    if (_error) ...[const Text('Registrations unavailable. Check access and connection.'), TextButton(onPressed: () => _load(more: _rows.isNotEmpty), child: const Text('Retry registrations'))],
    if (!_busy && !_error && _rows.isEmpty) const Text('No registrations requiring attention in this queue.'),
    if (!_busy && !_error && _cursor != null) TextButton(onPressed: () => _load(more: true), child: const Text('Load more registrations')),
  ]);
}

class PendingRegistrationsEntry extends StatefulWidget {
  const PendingRegistrationsEntry({super.key, required this.admin, this.service});
  final AdminService admin;
  final AdminRegistrationQueueService? service;
  @override
  State<PendingRegistrationsEntry> createState() => _PendingRegistrationsEntryState();
}
class _PendingRegistrationsEntryState extends State<PendingRegistrationsEntry> {
  late final _service = widget.service ?? AdminRegistrationQueueService(admin: widget.admin);
  late Future<RegistrationQueueCounts> _counts = _service.counts();
  Future<void> _open(RegistrationQueueFilter filter) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AdminRegistrationQueueScreen(service: _service, initialFilter: filter)));
    if (mounted) { setState(() { _counts = _service.counts(); }); }
  }
  @override
  Widget build(BuildContext context) => FutureBuilder<RegistrationQueueCounts>(future: _counts, builder: (_, snapshot) => Card(child: Column(children: [
    ListTile(title: const Text('Pending Registrations'), subtitle: const Text('Review applications and corrections'),
      trailing: Text(snapshot.hasData ? '${snapshot.data!.identity}' : '—'), onTap: () => _open(RegistrationQueueFilter.all)),
    ListTile(title: const Text('Payment & Activation'), subtitle: Text(snapshot.hasData ? 'Pending payments shown in badge · ${snapshot.data!.activation} awaiting membership activation' : 'Payment & Membership'),
      trailing: Text(snapshot.hasData ? '${snapshot.data!.payment}' : '—'), onTap: () => _open(RegistrationQueueFilter.payment)),
    if (snapshot.hasError) const Text('Queue counts unavailable.'),
    TextButton(onPressed: snapshot.connectionState == ConnectionState.waiting ? null : () => setState(() { _counts = _service.counts(); }), child: const Text('Refresh queue counts')),
  ])));
}
