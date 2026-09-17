import 'package:flutter/material.dart';
import '../../app/app_text_styles.dart';
import '../../core/models/admin_support_data.dart';
import '../../core/models/support_message.dart';
import '../../core/models/support_request.dart';
import '../../core/services/admin_support_service.dart';
import '../../core/widgets/admin_support_components.dart';
import '../../core/widgets/app_components.dart';

class AdminSupportDetailScreen extends StatefulWidget {
  const AdminSupportDetailScreen({super.key, required this.requestId, this.service});
  final String requestId;
  final AdminSupportService? service;
  @override
  State<AdminSupportDetailScreen> createState() => _AdminSupportDetailScreenState();
}
class _AdminSupportDetailScreenState extends State<AdminSupportDetailScreen> {
  late final _service = widget.service ?? AdminSupportService();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Support request')),
    body: AdminSupportGate(service: _service, builder: (context, uid) =>
      _Thread(key: ValueKey(widget.requestId), id: widget.requestId, service: _service)),
  );
}

class _Thread extends StatefulWidget {
  const _Thread({super.key, required this.id, required this.service});
  final String id;
  final AdminSupportService service;
  @override
  State<_Thread> createState() => _ThreadState();
}
class _ThreadState extends State<_Thread> {
  final _reply = TextEditingController();
  SupportRequest? _request;
  final _messages = <SupportMessage>[];
  final _history = <SupportStatusEvent>[];
  SupportCursor? _nextMessage, _nextHistory;
  String? _selectedStatus, _error, _notice, _replyOperation, _statusOperation, _statusOperationKey;
  bool _loading = true, _loadFailed = false, _saving = false, _paging = false;
  int _generation = 0;
  bool get _busy => _loading || _saving || _paging;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _generation++; _reply.dispose(); super.dispose(); }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true; _loadFailed = false; _error = null; _request = null;
      _messages.clear(); _history.clear(); _nextMessage = null; _nextHistory = null;
    });
    try {
      final detail = await widget.service.loadDetail(widget.id);
      if (!mounted || generation != _generation) return;
      setState(() {
        _request = detail?.request;
        if (detail != null) {
          _messages.addAll(detail.messages.items); _history.addAll(detail.history.items);
          _nextMessage = detail.messages.next; _nextHistory = detail.history.next;
        }
        _selectedStatus = supportStatuses.containsKey(_request?.status) ? _request!.status : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() { _loadFailed = true; _loading = false; });
    }
  }

  Future<void> _more({required bool history}) async {
    if (_busy) return;
    final cursor = history ? _nextHistory : _nextMessage;
    if (cursor == null) return;
    final generation = _generation;
    setState(() { _paging = true; _error = null; });
    try {
      if (history) {
        final page = await widget.service.loadHistory(widget.id, cursor);
        if (!mounted || generation != _generation) return;
        setState(() {
          final ids = _history.map((e) => e.id).toSet();
          _history.addAll(page.items.where((e) => ids.add(e.id))); _nextHistory = page.next;
        });
      } else {
        final page = await widget.service.loadMessages(widget.id, cursor);
        if (!mounted || generation != _generation) return;
        setState(() {
          final ids = _messages.map((e) => e.id).toSet();
          _messages.addAll(page.items.where((e) => ids.add(e.id))); _nextMessage = page.next;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'Could not load more. Use Load more to retry.');
    } finally {
      if (mounted && generation == _generation) setState(() => _paging = false);
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _reply.text.trim();
    if (text.isEmpty || text.length > 4000) {
      setState(() => _error = 'Write a reply of 1 to 4000 characters.');
      return;
    }
    setState(() { _saving = true; _error = null; _notice = null; });
    try {
      _replyOperation ??= widget.service.newOperationId();
      await widget.service.reply(widget.id, text, operationId: _replyOperation!);
      if (!mounted) return;
      _reply.clear(); _replyOperation = null;
      setState(() => _notice = 'Reply sent. Conversation reloaded from the beginning.');
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Reply not confirmed. Refresh to check the conversation or retry the same reply.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus() async {
    final request = _request, next = _selectedStatus;
    if (_busy || request == null || next == null || next == request.status) return;
    setState(() { _saving = true; _error = null; _notice = null; });
    try {
      final key = '${request.status}:$next';
      if (_statusOperationKey != key) {
        _statusOperation = widget.service.newOperationId(); _statusOperationKey = key;
      }
      await widget.service.changeStatus(widget.id, request.status, next, operationId: _statusOperation!);
      if (!mounted) return;
      _statusOperation = null; _statusOperationKey = null;
      setState(() => _notice = 'Status updated and recorded in history.');
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Status update not confirmed. Refresh for the latest status before trying again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading support conversation'));
    if (_loadFailed) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Text('Support conversation unavailable. Check your access and connection.'),
          TextButton(onPressed: _saving ? null : _load, child: const Text('Retry conversation')),
        ])));
    }
    final request = _request;
    if (request == null) {
      return const Center(child: AppEmptyState(title: 'Request not found',
        message: 'This support request is no longer available.', icon: Icons.support_agent));
    }
    return ListView(padding: appPagePadding(context), children: [
      Row(children: [Expanded(child: AppSectionHeader(request.supportReference)),
        IconButton(tooltip: 'Refresh conversation', onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
      AppInfoCard(children: [
        Text(request.subject, style: AppTextStyles.cardTitle),
        Text(supportCategoryLabel(request)),
        AppStatusChip(supportStatuses[request.status] ?? request.status),
        const SizedBox(height: 12),
        SelectableText('Requester: ${request.userName} (${request.userRole})'),
        SelectableText('User ID: ${request.userId}'),
        SelectableText('Contact snapshot: ${request.contactNumber}'),
        if (request.tripReference != null) SelectableText('Trip: ${request.tripReference}'),
        Text('Created: ${adminSupportDate(context, request.createdAt)}'),
        Text('Updated: ${adminSupportDate(context, request.updatedAt)}'),
        Text('Last message: ${adminSupportDate(context, request.lastMessageAt)}'),
      ]),
      AppInfoCard(children: [const AppSectionHeader('Original request'), SelectableText(request.message)]),
      AppInfoCard(children: [const AppSectionHeader('Automatic acknowledgement'), Text(request.acknowledgement)]),
      AppSectionHeader('Conversation', subtitle: '${_messages.length} messages loaded · Oldest first'),
      if (_messages.isEmpty) const Text('No replies yet.'),
      ..._messages.map((message) => AppInfoCard(children: [
        Text(switch (message.senderRole) { 'admin' => 'Support team', 'user' => 'Requester',
          'system' => 'System', _ => 'Unknown sender' }, style: AppTextStyles.cardTitle),
        Text('Sender ID: ${message.senderId}', style: AppTextStyles.caption),
        SelectableText(message.message), Text(adminSupportDate(context, message.createdAt)),
      ])),
      if (_nextMessage != null) OutlinedButton(onPressed: _busy ? null : () => _more(history: false),
        child: const Text('Load more messages')),
      if (_nextMessage == null) const Text('All messages loaded. Refresh to check for new replies.'),
      const SizedBox(height: 16),
      if (request.status == 'closed') const Text('This request is closed. Reopen it to reply.') else ...[
        TextField(key: const Key('admin_support_reply'), controller: _reply, enabled: !_busy,
          onChanged: (_) { _replyOperation = null; }, maxLength: 4000, minLines: 2, maxLines: 6,
          decoration: const InputDecoration(labelText: 'Reply as support team', border: OutlineInputBorder())),
        FilledButton(key: const Key('admin_support_send'), onPressed: _busy ? null : _send,
          child: const Text('Send reply')),
      ],
      const AppSectionHeader('Request status', spacious: true),
      DropdownButtonFormField<String>(key: ValueKey('status_${request.status}'),
        initialValue: _selectedStatus, isExpanded: true, decoration: const InputDecoration(labelText: 'Status'),
        items: supportStatuses.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
        onChanged: _busy ? null : (value) => setState(() => _selectedStatus = value)),
      OutlinedButton(key: const Key('admin_support_status'),
        onPressed: _busy || _selectedStatus == null || _selectedStatus == request.status ||
          !supportStatuses.containsKey(request.status) ? null : _changeStatus,
        child: const Text('Update status')),
      if (_saving || _paging) const LinearProgressIndicator(),
      if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
      if (_notice != null) Text(_notice!),
      AppSectionHeader('Status history', spacious: true, subtitle: '${_history.length} changes loaded · Oldest first'),
      if (_history.isEmpty) const Text('No recorded status changes. Earlier changes may predate audit history.'),
      ..._history.map((event) => AppInfoCard(children: [
        Text('${supportStatuses[event.fromStatus] ?? event.fromStatus} → ${supportStatuses[event.toStatus] ?? event.toStatus}'),
        SelectableText('Staff UID: ${event.actorId}'), Text(adminSupportDate(context, event.createdAt)),
      ])),
      if (_nextHistory != null) OutlinedButton(onPressed: _busy ? null : () => _more(history: true),
        child: const Text('Load more history')),
    ]);
  }
}
