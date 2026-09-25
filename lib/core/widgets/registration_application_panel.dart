import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/registration_application.dart';
import '../models/driver_administration.dart';
import '../services/registration_application_service.dart';
import '../services/driver_administration_service.dart';
import '../services/driver_evidence_service.dart';
import '../services/evidence_image_service.dart';
import '../services/bid_service.dart';
import '../validation/registration_validation.dart';
import 'app_components.dart';
import 'driver_evidence_widgets.dart';
import 'driver_administration_panel.dart';

class RegistrationApplicationPanel extends StatefulWidget {
  const RegistrationApplicationPanel({super.key, required this.uid, this.admin = false, this.service, this.evidenceService, this.images, this.onChanged});
  final String uid;
  final bool admin;
  final RegistrationApplicationService? service;
  final DriverEvidenceService? evidenceService;
  final EvidenceImageService? images;
  final VoidCallback? onChanged;
  @override
  State<RegistrationApplicationPanel> createState() => _RegistrationApplicationPanelState();
}

class _RegistrationApplicationPanelState extends State<RegistrationApplicationPanel> {
  late final _service = widget.service ?? RegistrationApplicationService();
  late final _evidenceService = widget.evidenceService ?? DriverEvidenceService(registrationApplication: true);
  final _form = GlobalKey<FormState>();
  final _fields = {for (final key in ['fullName', 'phoneNumber', 'city', 'vehicleNumber', 'operatingArea', 'availableAreas', 'nicNumber', 'drivingLicenceNumber']) key: TextEditingController()};
  final _paths = <String, String>{}, _busyPhotos = <String>{}, _notReady = <String>{};
  RegistrationApplicationData? _data;
  final _history = <Map<String, dynamic>>[];
  Map<String, dynamic>? _historicalSubmission;
  bool _moreHistory = false;
  String? _vehicle, _message, _operationId, _signature;
  bool _loading = true, _saving = false, _accepted = false, _uncertain = false;
  int _generation = 0;
  bool get _enabled => !_loading && !_saving && !_uncertain && _busyPhotos.isEmpty && !(_data?.pendingOperation ?? true);
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _generation++; for (final controller in _fields.values) { controller.dispose(); } super.dispose(); }
  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _data = null; _paths.clear(); _busyPhotos.clear(); _notReady.clear(); _accepted = false;
      _history.clear(); _historicalSubmission = null; _moreHistory = false; });
    try {
      final data = await _service.load(widget.uid, admin: widget.admin);
      if (!mounted || generation != _generation) { return; }
      for (final entry in _fields.entries) {
        // Re-enter private numbers for corrections; never place complete identity in a status summary.
        entry.value.text = ['nicNumber', 'drivingLicenceNumber'].contains(entry.key)
          ? '' : DriverAdministration.text(data.profile[entry.key], '');
      }
      setState(() { _data = data; _vehicle = data.profile['vehicleType'] is String ? data.profile['vehicleType'] as String : null;
        _history.addAll(data.history); _moreHistory = data.history.length == 20;
        _uncertain = false; _operationId = null; _signature = null; });
    } catch (_) { if (mounted && generation == _generation) { setState(() => _message = 'Application unavailable. Check your access and connection, then refresh.'); } }
    finally { if (mounted && generation == _generation) { setState(() => _loading = false); } }
  }
  Future<void> _perform(String action, Map<String, dynamic> payload, {String reason = ''}) async {
    final data = _data;
    if (!_enabled || data == null) { return; }
    setState(() { _saving = true; _message = null; });
    try {
      final signature = jsonEncode([action, payload, data.revision, reason]);
      if (_signature != signature) { _signature = signature; _operationId = _service.newOperationId(widget.uid); }
      await _service.perform(widget.uid, action, payload, revision: data.revision, operationId: _operationId!, admin: widget.admin, reason: reason);
      if (!mounted) { return; }
      setState(() => _message = 'Application action confirmed.');
      await _load();
      if (mounted) { widget.onChanged?.call(); }
    } on DriverAdministrationException catch (e) {
      // A recorded domain failure is final. An explicit retry needs a fresh ID;
      // uncertain transport outcomes below remain locked until refresh.
      if (mounted) { setState(() { _message = e.message; _operationId = null; _signature = null; }); }
    } catch (_) {
      if (mounted) { setState(() { _uncertain = true; _message = 'Result not confirmed. Refresh to check the application before submitting again.'; }); }
    } finally { if (mounted) { setState(() => _saving = false); } }
  }
  Future<void> _submit(bool driver) async {
    if (!_enabled) { return; }
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      final first = invalid.first;
      setState(() => _message = first.errorText);
      await Scrollable.ensureVisible(first.context, duration: const Duration(milliseconds: 200), alignment: .2);
      return;
    }
    final error = validateApplicationSubmission(driver: driver, nic: _fields['nicNumber']!.text,
      licence: _fields['drivingLicenceNumber']!.text, evidence: _paths, agreement: _accepted);
    if (error != null || _notReady.isNotEmpty) { setState(() => _message = error ?? 'Upload or remove the selected replacement photos.'); return; }
    final profile = {for (final key in ['fullName', 'phoneNumber', 'city', if (driver) ...['vehicleNumber', 'operatingArea', 'availableAreas']]) key: _fields[key]!.text.trim(),
      if (driver) 'vehicleType': _vehicle};
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Review application'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(driver ? 'Driver application' : 'Tourist/User application'),
          for (final entry in profile.entries) Text('${entry.key}: ${entry.value}'),
          Text('Required photos ready: ${requiredApplicationEvidence(driver).length}'),
          const Text('Please check your details and photo previews. Submission starts manual review and does not approve your account.'),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back to edit')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit Application'))]));
    if (!mounted || confirmed != true || !_enabled) { return; }
    await _perform('submit_application', {'profile': profile, 'nicNumber': _fields['nicNumber']!.text.trim(),
      if (driver) 'drivingLicenceNumber': _fields['drivingLicenceNumber']!.text.trim(), 'evidence': Map<String, String>.from(_paths),
      'agreementVersion': registrationAgreementVersion, 'agreementAccepted': true});
  }
  Future<void> _review(String action, String label) async {
    var reason = '';
    final form = GlobalKey<FormState>();
    final approved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(label),
      content: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Review the current private documents and information before confirming. Driver payment and membership remain separate.'),
        if (action != 'approve') TextFormField(onChanged: (value) => reason = value, maxLength: 500, decoration: const InputDecoration(labelText: 'Reason shown to applicant'),
          validator: (value) => value == null || value.trim().isEmpty ? 'A reason is required.' : null),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () { if (form.currentState!.validate()) { Navigator.pop(context, true); } }, child: const Text('Confirm'))]));
    final message = reason.trim();
    if (mounted && approved == true) { await _perform(action, {}, reason: message); }
  }
  Future<void> _readHistory({int? revision}) async {
    if (_saving) { return; }
    final generation = _generation;
    setState(() => _saving = true);
    try {
      if (revision != null) {
        final submission = await _service.loadSubmission(widget.uid, revision, admin: widget.admin);
        if (mounted && generation == _generation) { setState(() => _historicalSubmission = submission); }
      } else if (_history.isNotEmpty) {
        final page = await _service.loadHistory(widget.uid, admin: widget.admin, after: _history.last);
        if (mounted && generation == _generation) {
          setState(() {
            final ids = _history.map((e) => e['operationId']).toSet();
            _history.addAll(page.where((e) => ids.add(e['operationId'])));
            _moreHistory = page.length == 20;
          });
        }
      }
    } catch (_) {
      if (mounted && generation == _generation) { setState(() => _message = 'Application history unavailable. Please retry.'); }
    } finally { if (mounted && generation == _generation) { setState(() => _saving = false); } }
  }
  Widget _input(String key, String label) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: TextFormField(
    key: ValueKey('application_$key'), controller: _fields[key], enabled: _enabled, autocorrect: false, enableSuggestions: false,
    maxLength: key == 'phoneNumber' || key == 'nicNumber' || key == 'drivingLicenceNumber' ? 40 : 120,
    decoration: InputDecoration(labelText: label), validator: (value) {
      if (key == 'phoneNumber') { return validateRegistrationPhone(value ?? ''); }
      return value == null || value.trim().isEmpty ? 'Enter $label.' : null;
    }));
  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_loading) { return const Center(child: CircularProgressIndicator()); }
    if (data == null) { return Column(children: [Text(_message ?? 'Application unavailable.'), TextButton(onPressed: _load, child: const Text('Refresh application'))]); }
    if (data.status == 'legacy') {
      return const Text('This account uses the existing registration workflow. Contact support if your account is unavailable.');
    }
    final driver = data.profile['accountType'] == 'driver';
    final app = data.application ?? {};
    final editable = !widget.admin && ['draft', 'correction_required', 'rejected'].contains(data.status);
    return AppInfoCard(children: [
      Row(children: [const Expanded(child: AppSectionHeader('Registration application')),
        IconButton(onPressed: _saving || _busyPhotos.isNotEmpty ? null : _load, tooltip: 'Refresh application', icon: const Icon(Icons.refresh))]),
      Text('Status: ${data.status.replaceAll('_', ' ')}'), Text('Application revision: ${data.revision}'),
      Text('Account status: ${data.profile['accountStatus'] ?? 'Not available'}'),
      if (_saving) const LinearProgressIndicator(),
      if (_message != null) Text(_message!),
      if (app['reason'] is String) Text('Review reason: ${app['reason']}'),
      for (final op in data.operations.where((op) => op['status'] == 'failed').take(3))
        Text('Previous action: ${DriverAdministration.text(op['errorMessage'], 'Action could not be processed.')}'),
      if (data.pendingOperation || _uncertain) const Text('An application action may still be queued. Refresh before another submission.'),
      if (data.status == 'pending_review') const Text('Application submitted for manual review. Submission does not mean approval.'),
      if (widget.admin) ...[
        for (final key in ['nicNumber', if (driver) 'drivingLicenceNumber', 'agreementVersion', 'agreementAcceptedAt', 'submittedAt', 'reviewedBy', 'reviewedAt'])
          SelectableText('$key: ${DriverAdministration.display(app[key])}'),
        if (app['profile'] is Map) for (final entry in (app['profile'] as Map).entries) SelectableText('${entry.key}: ${entry.value}'),
      ],
      if (app['evidence'] is List) DriverEvidenceReview(uid: widget.uid, evidence: app['evidence'] as List, service: _evidenceService),
      if (widget.admin && data.status == 'pending_review') Wrap(spacing: 8, children: [
        for (final item in const {'approve': 'Approve application', 'reject': 'Reject application', 'request_correction': 'Request correction'}.entries)
          OutlinedButton(onPressed: _enabled ? () => _review(item.key, item.value) : null, child: Text(item.value)),
      ]),
      if (editable) Form(key: _form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (data.status != 'draft') const Text(registrationResubmissionMessage),
        const Text('Basic information'),
        _input('fullName', 'Full name'), _input('phoneNumber', 'Phone number'), _input('city', 'City / District'),
        Text('Login email: ${data.profile['email'] ?? ''}'),
        if (driver) ...[
          DropdownButtonFormField<String>(initialValue: BidService.vehicleTypes.contains(_vehicle) ? _vehicle : null,
            isExpanded: true, decoration: const InputDecoration(labelText: 'Vehicle type'),
            items: [for (final type in BidService.vehicleTypes) DropdownMenuItem(value: type, child: Text(type))],
            onChanged: _enabled ? (value) => setState(() => _vehicle = value) : null,
            validator: (value) => value == null ? 'Choose a vehicle type.' : null),
          _input('vehicleNumber', 'Vehicle number'), _input('operatingArea', 'Operating area'), _input('availableAreas', 'Available areas'),
        ],
        const AppSectionHeader('Identity information'),
        _input('nicNumber', 'NIC number'), if (driver) _input('drivingLicenceNumber', 'Driving Licence number'),
        const Text('These details and photos are private and used for manual verification. All photos below are required.'),
        for (final type in EvidenceType.values.where((t) => t != EvidenceType.paymentSlip && (driver || t != EvidenceType.drivingLicence)))
          DriverEvidenceUpload(key: ValueKey('application_${data.revision}_${type.stored}'), uid: widget.uid, revision: data.revision + 1,
            type: type, enabled: _enabled, service: _evidenceService, images: widget.images,
            onChange: (path) => setState(() { if (path == null) { _paths.remove(type.stored); } else { _paths[type.stored] = path; } }),
            onState: (busy, ready) => setState(() {
              if (busy) { _busyPhotos.add(type.stored); } else { _busyPhotos.remove(type.stored); }
              if (ready) { _notReady.remove(type.stored); } else { _notReady.add(type.stored); }
            })),
        const AppSectionHeader('Registration Guidelines & Agreement'),
        const Text('Version 1.0 — application guidelines'),
        for (final guideline in registrationGuidelines) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('• $guideline')),
        CheckboxListTile(key: const ValueKey('registrationAgreement'), contentPadding: EdgeInsets.zero, value: _accepted,
          onChanged: _enabled ? (value) => setState(() => _accepted = value ?? false) : null,
          title: const Text('I confirm my information is accurate and accept these guidelines and manual verification.')),
        FilledButton(key: const ValueKey('reviewApplication'), onPressed: _enabled ? () => _submit(driver) : null,
          child: const Text('Review application')),
      ])),
      if (!widget.admin && driver && data.status == 'approved') ...[
        if (!driverCanBid(data.profile)) Text(driverActivationMessage(data.profile)),
        DriverAdministrationPanel(key: ValueKey('membership_${data.revision}'), uid: widget.uid, admin: false),
      ],
      if (_history.isNotEmpty) ExpansionTile(title: const Text('Application history'), children: [
        for (final event in _history) ListTile(
          title: Text('${event['action']} · revision ${event['applicationRevision']}'),
          subtitle: Text('${event['previousValue']} → ${event['newValue']}\n'
            '${DriverAdministration.display(event['createdAt'])}\n'
            '${event['reason'] ?? ''}${widget.admin ? '\nActor: ${event['actorUid']}' : ''}'),
          onTap: event['applicationRevision'] is int && !_saving ? () => _readHistory(revision: event['applicationRevision'] as int) : null),
        if (_moreHistory) TextButton(onPressed: _saving ? null : _readHistory, child: const Text('Load earlier history')),
      ]),
      if (_historicalSubmission case final submission?) AppInfoCard(children: [
        Text('Submitted revision ${submission['applicationRevision']} (immutable)'),
        Text('Agreement: ${submission['agreementVersion']} · ${DriverAdministration.display(submission['agreementAcceptedAt'])}'),
        if (widget.admin) ...[
          SelectableText('NIC: ${DriverAdministration.display(submission['nicNumber'])}'),
          if (driver) SelectableText('Driving Licence: ${DriverAdministration.display(submission['drivingLicenceNumber'])}'),
          if (submission['profile'] is Map) for (final entry in (submission['profile'] as Map).entries)
            SelectableText('${entry.key}: ${entry.value}'),
        ],
        if (submission['evidence'] is List) DriverEvidenceReview(key: ValueKey(submission['applicationRevision']),
          uid: widget.uid, evidence: submission['evidence'] as List, service: _evidenceService),
        TextButton(onPressed: () => setState(() => _historicalSubmission = null), child: const Text('Close submitted revision')),
      ]),
    ]);
  }
}
