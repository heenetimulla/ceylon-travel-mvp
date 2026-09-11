import 'package:flutter/material.dart';
import '../../core/models/support_request.dart';
import '../../core/models/support_message.dart';
import '../../core/models/trip_post.dart';
import '../../core/services/support_service.dart';
import '../../core/validation/registration_validation.dart';
import '../../core/widgets/app_components.dart';

class SupportFormScreen extends StatefulWidget {
  const SupportFormScreen({super.key, this.trip, this.byCreator = true, this.loadProfile, this.onSubmit});
  final TripPost? trip;
  final bool byCreator;
  final Future<Map<String, dynamic>> Function()? loadProfile;
  final Future<String> Function(String category, String? subCategory, String phone, String subject, String message, String? manualReference)? onSubmit;
  @override
  State<SupportFormScreen> createState() => _SupportFormScreenState();
}
class _SupportFormScreenState extends State<SupportFormScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController(), _subject = TextEditingController(), _message = TextEditingController(), _reference = TextEditingController();
  String _category = 'question';
  String? _subCategory, _error;
  bool _loading = true, _saving = false, _phoneEdited = false;
  @override
  void initState() { super.initState(); if (widget.trip != null) _category = 'complaint'; _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final profile = await (widget.loadProfile?.call() ?? SupportService().loadProfile());
      if (!mounted) return;
      if (!_phoneEdited) _phone.text = profile['phoneNumber'] as String? ?? '';
    } catch (_) { if (mounted) setState(() => _error = 'Could not load your contact number. You can enter it below.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  @override
  void dispose() { _phone.dispose(); _subject.dispose(); _message.dispose(); _reference.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final id = widget.onSubmit != null
        ? await widget.onSubmit!(_category, _subCategory, _phone.text.trim(), _subject.text.trim(), _message.text.trim(), _reference.text.trim())
        : await SupportService().create(category: _category, contactNumber: _phone.text, subject: _subject.text,
            message: _message.text, subCategory: _subCategory, tripId: widget.trip?.id,
            manualTripReference: widget.trip == null && _category == 'complaint' ? _reference.text : null);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SupportThreadScreen(requestId: id)));
    } catch (_) { if (mounted) setState(() => _error = 'Could not submit your request. Check your connection and try again.'); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) {
    final categories = widget.byCreator ? creatorComplaintCategories : driverComplaintCategories;
    return Scaffold(appBar: AppPageAppBar(title: Text(widget.trip == null ? 'Contact Us / Support' : 'Report / Complain about this trip')),
      body: ListView(padding: appPagePadding(context), children: [AppInfoCard(children: [
        if (widget.trip != null) ...[Text(widget.trip!.referenceLabel), const SizedBox(height: 16)],
        Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.trip == null) DropdownButtonFormField<String>(initialValue: _category, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: supportCategories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: _saving ? null : (v) => setState(() => _category = v!),
          ),
          if (widget.trip != null) DropdownButtonFormField<String>(isExpanded: true,
            decoration: const InputDecoration(labelText: 'Complaint category'),
            items: categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            validator: (v) => categories.containsKey(v) ? null : 'Choose a category.',
            onChanged: _saving ? null : (v) => setState(() => _subCategory = v),
          ),
          const SizedBox(height: 16),
          if (widget.trip == null && _category == 'complaint') TextFormField(controller: _reference, maxLength: 40,
            enabled: !_saving, decoration: const InputDecoration(labelText: 'Trip Reference (optional)')),
          TextFormField(controller: _phone, enabled: !_saving && !_loading, keyboardType: TextInputType.phone,
            onChanged: (_) => _phoneEdited = true, validator: (v) => validateRegistrationPhone(v ?? ''),
            decoration: const InputDecoration(labelText: 'Contact Number', helperText: 'We may call this number regarding this request.', helperMaxLines: 2)),
          const SizedBox(height: 16),
          TextFormField(controller: _subject, enabled: !_saving, maxLength: 160,
            decoration: const InputDecoration(labelText: 'Subject'), validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a subject.' : null),
          TextFormField(controller: _message, enabled: !_saving, maxLength: 4000, maxLines: 6,
            decoration: const InputDecoration(labelText: 'Message'), validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your message.' : null),
          if (_error != null) Text(_error!),
          FilledButton(onPressed: _saving || _loading ? null : _save, child: Text(_saving ? 'Submitting...' : 'Submit Request')),
        ])),
      ])]),
    );
  }
}

class SupportRequestsScreen extends StatefulWidget {
  const SupportRequestsScreen({super.key, this.requestsStream});
  final Stream<List<SupportRequest>>? requestsStream;
  @override
  State<SupportRequestsScreen> createState() => _SupportRequestsScreenState();
}
class _SupportRequestsScreenState extends State<SupportRequestsScreen> {
  late final _requests = widget.requestsStream ?? SupportService().watchOwnRequests();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('My Support Requests')),
    body: ListView(padding: appPagePadding(context), children: [
      FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupportFormScreen())), icon: const Icon(Icons.support_agent), label: const Text('Contact Us / Support')),
      const SizedBox(height: 16),
      StreamBuilder<List<SupportRequest>>(stream: _requests, builder: (context, snapshot) {
        if (snapshot.hasError) return const AppEmptyState(title: 'Requests unavailable', message: 'Please reopen this page to try again.');
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.isEmpty) return const AppEmptyState(title: 'No support requests', message: 'Contact us whenever you need help.');
        return Column(children: [for (final request in snapshot.data!) Card(child: ListTile(
          title: Text(request.supportReference),
          subtitle: Text('${supportCategories[request.category]} ? ${request.status.replaceAll('_', ' ')}\n${request.lastMessageAt?.toLocal().toString() ?? 'Sending...'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupportThreadScreen(requestId: request.id))),
        ))]);
      }),
    ]),
  );
}

class SupportThreadScreen extends StatefulWidget {
  const SupportThreadScreen({super.key, required this.requestId, this.requestStream, this.messagesStream, this.onReply});
  final String requestId;
  final Stream<SupportRequest>? requestStream;
  final Stream<List<SupportMessage>>? messagesStream;
  final Future<void> Function(String)? onReply;
  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}
class _SupportThreadScreenState extends State<SupportThreadScreen> {
  late final _request = widget.requestStream ?? SupportService().watchRequest(widget.requestId);
  late final _messages = widget.messagesStream ?? SupportService().watchMessages(widget.requestId);
  final _reply = TextEditingController();
  bool _sending = false;
  String? _error;
  @override
  void dispose() { _reply.dispose(); super.dispose(); }
  Future<void> _send() async {
    if (_sending || _reply.text.trim().isEmpty) return;
    setState(() { _sending = true; _error = null; });
    try {
      await (widget.onReply?.call(_reply.text.trim()) ?? SupportService().reply(widget.requestId, _reply.text));
      if (!mounted) return;
      _reply.clear();
    } catch (_) { if (mounted) setState(() => _error = 'Could not send your reply. Please try again.'); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Support conversation')),
    body: StreamBuilder<SupportRequest>(stream: _request, builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('This request is unavailable.'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      final request = snapshot.data!;
      return ListView(padding: appPagePadding(context), children: [
        AppInfoCard(children: [Text(request.supportReference), AppStatusChip(request.status),
          Text(request.subject), if (request.tripReference != null) Text('Trip: ${request.tripReference}'),
          Text('Contact Number: ${request.contactNumber}'),
        ]),
        AppInfoCard(children: [const Text('Automatic acknowledgement'), Text(request.acknowledgement)]),
        AppInfoCard(children: [const Text('Your request'), Text(request.message)]),
        StreamBuilder<List<SupportMessage>>(stream: _messages, builder: (context, messages) {
          if (messages.hasError) return const Text('Replies unavailable. Please reopen this conversation.');
          return Column(children: [for (final message in messages.data ?? <SupportMessage>[]) AppInfoCard(children: [
            Text(message.senderRole == 'admin' ? 'Support team' : message.senderRole == 'system' ? 'System' : 'You'),
            Text(message.message), Text(message.createdAt?.toLocal().toString() ?? 'Sending...'),
          ])]);
        }),
        if (request.status != 'closed') ...[
          TextField(key: const Key('support_reply_field'), controller: _reply, enabled: !_sending, maxLength: 4000, maxLines: 3, decoration: const InputDecoration(labelText: 'Reply')),
          if (_error != null) Text(_error!),
          FilledButton(key: const Key('support_send_reply_button'), onPressed: _sending ? null : _send, child: Text(_sending ? 'Sending...' : 'Send Reply')),
        ] else const Text('This request is closed.'),
      ]);
    }),
  );
}
