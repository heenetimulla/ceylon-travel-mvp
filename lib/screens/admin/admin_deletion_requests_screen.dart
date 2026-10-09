import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/services/account_deletion_service.dart';
import '../../core/services/admin_service.dart';
import '../../core/widgets/admin_access_gate.dart';
import '../../core/widgets/app_components.dart';

class AdminDeletionRequestsScreen extends StatefulWidget {
  const AdminDeletionRequestsScreen({super.key});
  @override
  State<AdminDeletionRequestsScreen> createState() => _AdminDeletionRequestsScreenState();
}
class _AdminDeletionRequestsScreenState extends State<AdminDeletionRequestsScreen> {
  final _admin = AdminService();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Account deletion requests')),
    body: AdminAccessGate(service: _admin, builder: (_, uid) => const _DeletionQueue()),
  );
}
class _DeletionQueue extends StatefulWidget {
  const _DeletionQueue();
  @override
  State<_DeletionQueue> createState() => _DeletionQueueState();
}
class _DeletionQueueState extends State<_DeletionQueue> {
  final _service = AccountDeletionService();
  String _status = 'pending';
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream = _query();
  Stream<QuerySnapshot<Map<String, dynamic>>> _query() {
    Query<Map<String, dynamic>> query = _service.db.collection('account_deletion_requests')
      .where('status', isEqualTo: _status).orderBy(FieldPath.documentId()).limit(30);
    if (_cursor != null) { query = query.startAfterDocument(_cursor!); }
    return query.snapshots();
  }
  void _refresh({String? status, DocumentSnapshot<Map<String, dynamic>>? cursor}) => setState(() {
    _status = status ?? _status; _cursor = cursor; _stream = _query();
  });
  @override
  Widget build(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.all(16), child: DropdownButton<String>(
      value: _status, isExpanded: true,
      items: ['pending', 'needs_clarification', 'approved', 'rejected', 'completed'].map((status) =>
        DropdownMenuItem(value: status, child: Text(deletionStatusLabel(status)))).toList(),
      onChanged: (value) { if (value != null) { _refresh(status: value); } })),
    Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) { return Center(child: TextButton(
          onPressed: _refresh, child: const Text('Queue unavailable. Retry'))); }
        if (!snapshot.hasData) { return const Center(child: CircularProgressIndicator()); }
        final docs = snapshot.data!.docs;
        return ListView(padding: appPagePadding(context), children: [
          if (docs.isEmpty) const Text('No requests on this page.'),
          for (final doc in docs) Card(child: ListTile(
            title: Text('Account: ${doc.id}'),
            subtitle: Text(deletionStatusLabel(doc.data()['status'] as String)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => _DeletionDetailScreen(uid: doc.id))))),
          if (_cursor != null) TextButton(onPressed: _refresh, child: const Text('First page')),
          if (docs.length == 30) TextButton(onPressed: () => _refresh(cursor: docs.last),
            child: const Text('Next page')),
        ]);
      })),
  ]);
}
class _DeletionDetailScreen extends StatefulWidget {
  const _DeletionDetailScreen({required this.uid});
  final String uid;
  @override
  State<_DeletionDetailScreen> createState() => _DeletionDetailScreenState();
}
class _DeletionDetailScreenState extends State<_DeletionDetailScreen> {
  final _admin = AdminService();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Review deletion request')),
    body: AdminAccessGate(service: _admin, builder: (_, adminUid) =>
      _DeletionReview(uid: widget.uid, adminUid: adminUid)),
  );
}
class _DeletionReview extends StatefulWidget {
  const _DeletionReview({required this.uid, required this.adminUid});
  final String uid, adminUid;
  @override
  State<_DeletionReview> createState() => _DeletionReviewState();
}
class _DeletionReviewState extends State<_DeletionReview> {
  final _service = AccountDeletionService();
  final _note = TextEditingController();
  final _userMessage = TextEditingController();
  late final _stream = _service.request(widget.uid).snapshots();
  bool _busy = false;
  String? _message;
  @override
  void dispose() { _note.dispose(); _userMessage.dispose(); super.dispose(); }
  Future<void> _review(Map<String, dynamic> data, String action) async {
    if (_busy) { return; }
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(action == 'approve' ? 'Approve account deletion?' : action == 'complete'
        ? 'Complete irreversible deletion?' : 'Confirm review decision'),
      content: Text(action == 'approve'
        ? 'This disables account access and removes the current private profile. Resolve open trips first. '
          'Evidence and retained records require trusted operator cleanup before completion.'
        : action == 'complete' ? 'A backend-only cleanup and retention review record is required. '
          'The trusted worker will delete the authentication account. This cannot be undone.'
        : 'The status will be visible to the requester. Your private note will not be shown.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
      ],
    ));
    if (confirmed != true || !mounted) { return; }
    setState(() { _busy = true; _message = null; });
    try {
      await _service.review(widget.uid, data['revision'] as int, action, _note.text, _userMessage.text);
      if (mounted) { setState(() { _message = 'Review processed.'; _note.clear(); _userMessage.clear(); }); }
    } catch (error) {
      if (mounted) { setState(() { _message = deletionError(error); }); }
    } finally {
      if (mounted) { setState(() { _busy = false; }); }
    }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: _stream, builder: (context, snapshot) {
      if (snapshot.hasError) { return const Center(child: Text('Unable to load this request. Reopen to retry.')); }
      if (!snapshot.hasData) { return const Center(child: CircularProgressIndicator()); }
      final data = snapshot.data!.data();
      if (data == null) { return const Center(child: Text('Request unavailable.')); }
      final status = data['status'] as String;
      final canReview = ['pending', 'needs_clarification'].contains(status) && widget.uid != widget.adminUid;
      return ListView(padding: appPagePadding(context), children: [
        Text('Account: ${widget.uid}'),
        Text(deletionStatusLabel(status), style: Theme.of(context).textTheme.titleLarge),
        if (data['requestedAt'] is Timestamp) Text('Requested: ${(data['requestedAt'] as Timestamp).toDate().toLocal()}'),
        const SizedBox(height: 16),
        Text('Requester reason: ${data['reason'] ?? ''}'),
        if ((data['userMessage'] as String? ?? '').isNotEmpty)
          Text('Message to requester: ${data['userMessage']}'),
        const SizedBox(height: 12),
        const Text('Primary administrator review only. Resolve operational obligations before approval. '
          'Support staff cannot approve or complete deletion. Do not copy identity evidence here.'),
        if (status == 'approved') Text('Processing: ${data['processingStage'] ?? 'pending'}'),
        if (canReview || status == 'approved') ...[
          TextField(controller: _note, enabled: !_busy, maxLength: 1000, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Private admin note (not shown to requester)')),
          if (canReview) TextField(controller: _userMessage, enabled: !_busy, maxLength: 500, maxLines: 3,
            decoration: const InputDecoration(labelText: 'Message to requester',
              helperText: 'Required for rejection or clarification. Do not include private admin notes.')),
          if (canReview) Wrap(spacing: 8, children: [
            FilledButton(onPressed: _busy ? null : () => _review(data, 'approve'), child: const Text('Approve')),
            OutlinedButton(onPressed: _busy ? null : () => _review(data, 'reject'), child: const Text('Reject')),
            OutlinedButton(onPressed: _busy ? null : () => _review(data, 'request_clarification'),
              child: const Text('Request clarification')),
          ]),
          if (status == 'approved' && data['processingStage'] == 'manual_cleanup_required')
            FilledButton(onPressed: _busy ? null : () => _review(data, 'complete'),
              child: const Text('Complete after trusted cleanup')),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_message != null) Semantics(liveRegion: true, child: Text(_message!)),
      ]);
    });
}
