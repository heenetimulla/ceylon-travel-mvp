import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/services/account_deletion_service.dart';
import '../../core/widgets/app_components.dart';
import '../support/support_screens.dart';

class AccountDeletionScreen extends StatefulWidget {
  const AccountDeletionScreen({super.key});
  @override
  State<AccountDeletionScreen> createState() => _AccountDeletionScreenState();
}
class _AccountDeletionScreenState extends State<AccountDeletionScreen> {
  final _service = AccountDeletionService();
  final _password = TextEditingController();
  final _reason = TextEditingController();
  late final String? _uid;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>>? _request;
  late final StreamSubscription<Object?> _session;
  bool _invalidated = false, _confirmed = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _uid = _service.auth.currentUser?.uid;
    _request = _uid == null ? null : _service.request(_uid!).snapshots();
    _session = _service.auth.authStateChanges().listen((user) {
      if (user?.uid != _uid && mounted) {
        _password.clear(); _reason.clear();
        setState(() { _invalidated = true; });
      }
    });
  }
  @override
  void dispose() {
    unawaited(_session.cancel());
    _password.dispose(); _reason.dispose();
    super.dispose();
  }
  Future<void> _submit() async {
    if (!_confirmed || _uid == null || _busy) { return; }
    setState(() { _busy = true; _error = null; });
    try {
      await _service.submit(_uid!, _password.text, _reason.text);
      if (mounted) { setState(() { _confirmed = false; _reason.clear(); }); }
    } catch (error) {
      if (mounted) { setState(() { _error = deletionError(error); }); }
    } finally {
      if (mounted) { _password.clear(); setState(() { _busy = false; }); }
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Delete Account')),
    body: _uid == null || _invalidated
      ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(
        'Your session has ended. After approval, account access is disabled while deletion is processed.')))
      : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(stream: _request, builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(
            'Status is unavailable. Check your connection. Approved requests disable sign-in; contact support for follow-up.')));
        }
        if (!snapshot.hasData) { return const Center(child: CircularProgressIndicator()); }
        final data = snapshot.data!.data();
        final status = data?['status'] as String? ?? 'not_requested';
        final canSubmit = ['not_requested', 'rejected', 'needs_clarification'].contains(status);
        return ListView(padding: appPagePadding(context), children: [
          Text(deletionStatusLabel(status), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          const Text('This submits an account deletion request. It is different from logging out. '
            'Your account remains usable under its current restrictions until approval. '
            'After approval, sign-in and account use are disabled.'),
          const SizedBox(height: 12),
          const Text('Deletion may take time for review and processing. Trip, review, payment and audit records '
            'may be retained or anonymized where required for disputes, fraud prevention, accounting or legal obligations. '
            'Shared history belonging to other participants is protected.'),
          const SizedBox(height: 12),
          const Text('You can follow the request here while signed in. After access is disabled, '
            'follow-up requires support; completed accounts cannot sign in to view this page.'),
          if ((data?['userMessage'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 12), Text(data!['userMessage'] as String),
          ],
          if (status == 'needs_clarification' || status == 'rejected') ...[
            const SizedBox(height: 12),
            const Text('Review the message above. Add your clarification below to request another review, or contact support. '
              'Do not include passwords or identity documents.'),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => const SupportFormScreen())), child: const Text('Contact support')),
          ],
          if (canSubmit) ...[
            const SizedBox(height: 20),
            TextField(controller: _reason, enabled: !_busy, maxLength: 500, maxLines: 3,
              decoration: InputDecoration(labelText: status == 'needs_clarification'
                ? 'Clarification (optional)' : 'Reason (optional)')),
            TextField(controller: _password, enabled: !_busy, obscureText: true,
              autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'Current password')),
            CheckboxListTile(value: _confirmed, contentPadding: EdgeInsets.zero,
              onChanged: _busy ? null : (value) => setState(() { _confirmed = value ?? false; }),
              title: const Text('I understand and explicitly request deletion of my account.')),
            FilledButton(onPressed: _busy || !_confirmed ? null : _submit,
              child: Text(_busy ? 'Submitting request…' : 'Request account deletion')),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Semantics(liveRegion: true, child: Text(_error!))),
        ]);
      }),
  );
}
