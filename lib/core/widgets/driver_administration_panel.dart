import 'dart:convert';
import '../validation/driver_action_validation.dart';
import 'package:flutter/material.dart';
import '../models/driver_administration.dart';
import '../services/driver_administration_service.dart';
import 'app_components.dart';
import 'driver_evidence_widgets.dart';
import '../services/evidence_image_service.dart';
import '../services/driver_evidence_service.dart';

class DriverAdministrationPanel extends StatefulWidget {
  const DriverAdministrationPanel({super.key, required this.uid, required this.admin, this.service, this.showIdentity = true});
  final String uid;
  final bool admin;
  final DriverAdministrationService? service;
  final bool showIdentity;
  @override
  State<DriverAdministrationPanel> createState() => _DriverAdministrationPanelState();
}

class _DriverAdministrationPanelState extends State<DriverAdministrationPanel> {
  late final _service = widget.service ?? DriverAdministrationService();
  DriverAdministration? _data;
  final _payments = <DriverRecord>[], _history = <DriverRecord>[];
  bool _loading = true, _saving = false, _failed = false, _morePayments = false, _moreHistory = false;
  String? _message, _signature, _operationId;
  int _generation = 0;
  final _identityForm = GlobalKey<FormState>();
  final _nic = TextEditingController(), _licence = TextEditingController();
  bool _identityUnconfirmed = false;
  final _evidencePaths = <String, String>{};
  final _paymentPaths = <String, String>{};
  final _evidenceBusy = <String>{}, _evidenceNotReady = <String>{};
  bool get _pending => _data?.operations.any((op) => op.text('status') == 'pending') ?? false;
  bool get _enabled => !_loading && !_saving && !_pending && _evidenceBusy.isEmpty;
  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _generation++; _nic.dispose(); _licence.dispose(); super.dispose(); }
  Future<void> _load() async {
    final generation = ++_generation;
    setState(() { _loading = true; _failed = false; _data = null; _payments.clear(); _history.clear();
      _evidencePaths.clear(); _paymentPaths.clear(); _evidenceBusy.clear(); _evidenceNotReady.clear(); });
    try {
      final data = await _service.load(widget.uid, admin: widget.admin);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _data = data; _payments.addAll(data.payments); _history.addAll(data.history);
        _morePayments = data.payments.length == 20; _moreHistory = data.history.length == 20;
        _loading = false; _signature = null; _operationId = null;
        if (_identityUnconfirmed || _message == 'Identity submitted for admin review') { _message = null; }
        _identityUnconfirmed = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() { _loading = false; _failed = true; });
      }
    }
  }
  Future<void> _page(bool history) async {
    if (_saving || _loading) {
      return;
    }
    final rows = history ? _history : _payments;
    if (rows.isEmpty) {
      return;
    }
    final generation = _generation;
    setState(() => _saving = true);
    try {
      final page = await _service.page(widget.uid, history ? 'admin_history' : 'payments', rows.last, admin: widget.admin);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        final ids = rows.map((row) => row.id).toSet();
        rows.addAll(page.where((row) => ids.add(row.id)));
        if (history) { _moreHistory = page.length == 20; } else { _morePayments = page.length == 20; }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = 'History unavailable. Use Load more to retry.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
  Future<void> _action(String action, String title, Map<String, dynamic> payload,
      {Map<String, String> fields = const {}, String? explanation}) async {
    if (!_enabled || _data == null) {
      return;
    }
    final revision = _data!.revision;
    final values = await showDialog<Map<String, String>>(context: context, builder: (_) => DriverActionDialog(
      title: title, fields: fields, admin: widget.admin, reasonRequired: action == 'reject_payment', explanation: explanation ??
        'This action will be processed securely and recorded. Confirm that the information is correct.'));
    if (!mounted || values == null || !_enabled) {
      return;
    }
    final body = <String, dynamic>{...payload, ...values}..remove('reason');
    if (body.containsKey('claimedAmountLkr')) {
      body['claimedAmountLkr'] = int.tryParse(body['claimedAmountLkr'] as String);
    }
    final reason = values['reason'] ?? '';
    await _perform(action, body, revision, reason);
  }

  Future<void> _submitIdentity() async {
    if (!_enabled || _identityUnconfirmed || _evidenceNotReady.isNotEmpty || _data == null || _identityForm.currentState?.validate() != true) {
      return;
    }
    await _perform('submit_identity', {
      'nicNumber': _nic.text.trim(), 'drivingLicenceNumber': _licence.text.trim(),
      if (_evidencePaths.isNotEmpty) 'evidence': Map<String, String>.from(_evidencePaths),
    }, _data!.revision, '');
  }

  Future<void> _perform(String action, Map<String, dynamic> body, int revision, String reason) async {
    final signature = jsonEncode([action, body, revision, reason]);
    setState(() { _saving = true; _message = null; });
    try {
      if (_signature != signature) { _operationId = _service.newOperationId(widget.uid); _signature = signature; }
      await _service.perform(widget.uid, action, body, admin: widget.admin, revision: revision,
        operationId: _operationId!, reason: reason);
      if (!mounted) {
        return;
      }
      if (action == 'submit_identity') {
        _nic.clear();
        _licence.clear();
      }
      setState(() => _message = action == 'submit_identity'
        ? 'Identity submitted for admin review' : 'Action confirmed by the server.');
      await _load();
    } on DriverAdministrationException catch (error) {
      if (mounted) {
        setState(() { _message = error.message; _signature = null; _operationId = null; });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (action == 'submit_identity') { _identityUnconfirmed = true; }
          _message = 'Action not confirmed. It may still be queued. Refresh and check the operation result before trying again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _fields(Map<String, Object?> fields) => Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: fields.entries.map((entry) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
      child: SelectableText('${entry.key}: ${DriverAdministration.display(entry.value)}'))).toList());
  Widget _button(String key, String label, VoidCallback action, {bool allowed = true}) => OutlinedButton(
    key: ValueKey(key), onPressed: _enabled && allowed ? action : null, child: Text(label));

  String _masked(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return 'Not available';
    }
    final text = value.trim();
    return text.length <= 4 ? '****' : '${List.filled(text.length - 4, '*').join()}${text.substring(text.length - 4)}';
  }

  String? _identityValidation(String? value, String label) {
    final text = (value ?? '').trim();
    if (text.isEmpty) { return 'Enter your $label.'; }
    if (text.length > 40) { return 'Use no more than 40 characters.'; }
    // Format and normalization remain authoritative on the server.
    return null;
  }

  Widget _ownerIdentity(DriverAdministration data, Map<String, dynamic> identity) {
    if (data.profile.containsKey('registrationStatus')) {
      return AppInfoCard(children: [Text('Application identity status: ${data.identityStatus}'), const Text('Identity corrections and evidence are managed through your registration application.')]);
    }
    final status = data.identityStatus;
    final canSubmit = status != 'verified' && (data.identity == null || status == 'rejected');
    return AppInfoCard(children: [
      const AppSectionHeader('Identity verification'),
      const Text('Enter your NIC and driving licence numbers for private manual verification by an administrator. '
        'These details are not shown on your public profile.'),
      const SizedBox(height: 12),
      _fields({'Identity status': status}),
      if (data.identity != null) ...[
        _fields({'NIC': _masked(identity['nicNumber']), 'Driving licence': _masked(identity['drivingLicenceNumber'])}),
        if (status == 'pending') const Text('Identity submitted for admin review'),
        if (status == 'verified') const Text('Your identity has been verified.'),
        if (status == 'rejected') ...[
          const Text('Identity rejected. Correct your details below and submit again.'),
          _fields({'Rejection reason': identity['rejectionReason']}),
        ],
      ],
      const Text('You may attach private JPEG or PNG photos below. Check that document text and your face remain clear before uploading.'),
      if (identity['evidence'] is List) DriverEvidenceReview(uid: widget.uid, evidence: identity['evidence'] as List),
      if (canSubmit) Form(key: _identityForm, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextFormField(key: const ValueKey('driver_input_nicNumber'), controller: _nic,
          enabled: _enabled && !_identityUnconfirmed, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'NIC number'),
          validator: (value) => _identityValidation(value, 'NIC number')),
        const SizedBox(height: 12),
        TextFormField(key: const ValueKey('driver_input_drivingLicenceNumber'), controller: _licence,
          enabled: _enabled && !_identityUnconfirmed, autocorrect: false, enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'Driving licence number'),
          validator: (value) => _identityValidation(value, 'driving licence number')),
        const SizedBox(height: 12),
        for (final type in EvidenceType.values.where((type) => type != EvidenceType.paymentSlip)) DriverEvidenceUpload(key: ValueKey('${data.revision}_${type.stored}'),
          uid: widget.uid, revision: data.revision, type: type, enabled: _enabled && !_identityUnconfirmed,
          onChange: (path) => setState(() { if (path == null) { _evidencePaths.remove(type.stored); } else { _evidencePaths[type.stored] = path; } }),
          onState: (busy, ready) => setState(() {
            if (busy) { _evidenceBusy.add(type.stored); } else { _evidenceBusy.remove(type.stored); }
            if (ready) { _evidenceNotReady.remove(type.stored); } else { _evidenceNotReady.add(type.stored); }
          })),
        if (_evidenceNotReady.isNotEmpty) const Text('Upload or remove the selected photos before submitting.'),
        FilledButton(key: const ValueKey('submit_identity'), onPressed: _enabled && !_identityUnconfirmed && _evidenceNotReady.isEmpty ? _submitIdentity : null,
          child: Text(status == 'rejected' ? 'Resubmit identity' : 'Submit identity')),
      ])),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(
        child: CircularProgressIndicator(semanticsLabel: 'Loading driver administration')));
    }
    if (_failed) {
      return AppInfoCard(children: [const Text('Driver details unavailable. Check your access and connection.'),
        TextButton(onPressed: _saving ? null : _load, child: const Text('Retry driver details'))]);
    }
    final data = _data!;
    if (!data.isDriver) {
      return const SizedBox.shrink();
    }
    final identity = data.identity?.data ?? <String, dynamic>{};
    final profile = data.profile;
    if (profile.containsKey('registrationStatus') && profile['registrationStatus'] != 'approved') {
      return const Text('Driver payment and membership administration become available after application approval.');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [const Expanded(child: AppSectionHeader('Driver verification & membership')),
        IconButton(tooltip: 'Refresh driver details', onPressed: _saving || _evidenceBusy.isNotEmpty ? null : _load, icon: const Icon(Icons.refresh))]),
      if (_saving) const LinearProgressIndicator(),
      if (_message != null) Semantics(liveRegion: true, child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!))),
      if (_pending) const Text('An operation is queued. Refresh to check its result; further actions are paused.'),
      if (widget.admin) AppInfoCard(children: [const AppSectionHeader('Current verification state'),
        _fields({'Registration': DriverAdministration.text(profile['registrationStatus'], 'legacy').toUpperCase(),
          'Identity verification': data.identityStatus.toUpperCase(), 'Payment': data.paymentStatus.toUpperCase(),
          'Membership': DriverAdministration.display(profile['membershipStatus']).toUpperCase(),
          'Account': data.accountStatus.toUpperCase()})]),
      if (!widget.admin && !driverCanBid(profile)) const Text(driverEligibilityMessage),
      if (!widget.admin) _ownerIdentity(data, identity),
      if (widget.admin && widget.showIdentity) AppInfoCard(children: [const AppSectionHeader('Identity'),
        _fields({'Identity status': data.identityStatus, 'NIC': identity['nicNumber'],
          'Driving licence': identity['drivingLicenceNumber'], 'NIC document': identity['nicDocumentPath'],
          'Licence document': identity['drivingLicenceDocumentPath'], 'Selfie reference': identity['selfiePath'],
          'Submitted': identity['submittedAt'], 'Reviewed': identity['reviewedAt'], 'Reviewed by': identity['reviewedBy'],
          'Rejection reason': identity['rejectionReason']}),
        if (identity['evidence'] is List) DriverEvidenceReview(uid: widget.uid, evidence: identity['evidence'] as List),
        if (widget.admin && !profile.containsKey('registrationStatus')) Wrap(spacing: 8, runSpacing: 8, children: [
          _button('verify_identity', 'Verify identity', () => _action('verify_identity', 'Verify driver identity', {},
            explanation: 'Manually review the submitted NIC and driving licence numbers using your approved verification process. '
              'Open any uploaded photos privately and check readability. Confirm only after completing the manual review.'),
            allowed: data.identity != null && data.identityStatus != 'verified'),
          _button('reject_identity', 'Reject identity', () => _action('reject_identity', 'Reject driver identity', {}),
            allowed: data.identity != null && data.identityStatus != 'rejected'),
        ]),
      ]),
      AppInfoCard(children: [const AppSectionHeader('Payment & Membership'),
        _fields({'Payment status': data.paymentStatus, 'Verified registration total (LKR)': profile['registrationPaidTotalLkr'] ?? 0}),
        const Text('Registration payment activates this driver account, not individual trips. '
          'Your quoted fee and membership entitlement are locked when issued. A quote does not reserve a registration number.'),
        if (!widget.admin && profile['driverRegistrationNumber'] == null)
          _button('request_payment', 'Request payment reference', () => _action('request_payment', 'Request registration payment', {},
            explanation: 'The server will issue a registration quote and unique payment reference. Existing quote entitlement is preserved. '
              'Use it for your bank deposit or transfer where possible. No payment is made by this action.'),
            allowed: !_payments.any((payment) => payment.text('status') == 'pending')),
        if (_payments.isEmpty) const Text('No payment requests yet.'),
      ]),
      ..._payments.map((payment) => AppInfoCard(children: [
        AppSectionHeader(payment.text('paymentReference', payment.id)),
        _fields({'Driver': profile['fullName'], 'UID': widget.uid, 'Payment status': payment.data['status'],
          'Quoted registration fee (LKR)': payment.data['quotedRegistrationFeeLkr'],
          'Quoted membership plan': payment.data['quotedMembershipPlan'],
          'Quoted annual renewal required': payment.data['quotedAnnualRenewalRequired'],
          'Quoted annual renewal fee (LKR)': payment.data['quotedAnnualRenewalFeeLkr'],
          'Quote issued': payment.data['quotedAt'],
          'Expected amount (LKR)': payment.data['expectedAmountLkr'], 'Claimed amount (LKR)': payment.data['claimedAmountLkr'],
          'Claimed payment date': payment.data['claimedPaymentDate'], 'Transaction reference': payment.data['bankTransactionReference'],
          'Depositor': payment.data['depositorName'], 'Slip reference': payment.data['slipPath'],
          'Submitted': payment.data['submittedAt'], 'Verified': payment.data['verifiedAt'], 'Verified by': payment.data['verifiedBy'],
          'Bank record reference': payment.data['bankRecordReference'], 'Rejection reason': payment.data['rejectionReason']}),
        Text(payment.data['slipEvidence'] is Map ? 'Payment slip: uploaded' : 'Payment slip: no uploaded image available'),
        if (payment.data['slipEvidence'] is Map) DriverEvidenceReview(uid: widget.uid, evidence: [payment.data['slipEvidence']]),
        if (widget.admin && payment.text('status') == 'pending' && payment.data['claimSubmitted'] == true)
          Wrap(spacing: 8, runSpacing: 8, children: [
            _button('verify_payment_${payment.id}', 'Verify payment', () => _action('verify_payment', 'Verify registration payment',
              {'paymentId': payment.id}, fields: const {'bankRecordReference': 'Unique bank record reference'},
              explanation: 'Compare the amount, date, depositor and slip against actual bank records. '
                'Do not verify based only on the submitted slip. Confirm the bank transaction is not already used.')),
            _button('reject_payment_${payment.id}', 'Reject payment', () => _action('reject_payment', 'Reject registration payment', {'paymentId': payment.id})),
          ]),
        if (!widget.admin && payment.text('status') == 'pending' && payment.data['claimSubmitted'] != true)
          DriverEvidenceUpload(key: ValueKey('payment_${payment.id}_${data.revision}'), uid: widget.uid, revision: data.revision,
            type: EvidenceType.paymentSlip, enabled: _enabled, service: DriverEvidenceService(paymentId: payment.id),
            onChange: (path) => setState(() { if (path == null) { _paymentPaths.remove(payment.id); } else { _paymentPaths[payment.id] = path; } }),
            onState: (busy, ready) => setState(() {
              final key = 'payment_${payment.id}';
              if (busy) { _evidenceBusy.add(key); } else { _evidenceBusy.remove(key); }
              if (ready) { _evidenceNotReady.remove(key); } else { _evidenceNotReady.add(key); }
            })),
        if (!widget.admin && payment.text('status') == 'pending' && payment.data['claimSubmitted'] != true && !_paymentPaths.containsKey(payment.id))
          Text('Upload the payment slip before submitting.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (!widget.admin && payment.text('status') == 'pending' && payment.data['claimSubmitted'] != true)
          _button('submit_payment_${payment.id}', 'Submit payment claim', () => _action('submit_payment', 'Submit payment claim',
            {'paymentId': payment.id, 'slipPath': _paymentPaths[payment.id]},
            fields: const {'claimedAmountLkr': 'Claimed amount in whole LKR', 'claimedPaymentDate': 'Payment date (YYYY-MM-DD)',
              'bankTransactionReference': 'Bank transaction reference', 'depositorName': 'Depositor name'},
            explanation: 'Submit the transfer or deposit details with the uploaded slip for manual review. Submitted claims cannot be edited.'),
            allowed: _paymentPaths.containsKey(payment.id) && !_evidenceNotReady.contains('payment_${payment.id}')),
      ])),
      if (_morePayments) TextButton(onPressed: _saving ? null : () => _page(false), child: const Text('Load more payments')),
      AppInfoCard(children: [const AppSectionHeader('Membership'),
        _fields({'Registration number': profile['driverRegistrationNumber'], 'Plan': profile['membershipPlan'] ?? 'Assigned at activation',
          'Membership status': data.membershipStatus, 'Registration fee paid (LKR)': profile['registrationFeePaidLkr'],
          'Annual renewal required': profile['annualRenewalRequired'], 'Annual renewal fee (LKR)': profile['annualRenewalFeeLkr'],
          'Valid until': profile['membershipPlan'] == 'founding_lifetime' ? 'Lifetime — no expiry' : profile['membershipValidUntil']}),
        const Text('Quotes issued before the 100th activation preserve LKR 3,500 lifetime membership with no annual renewal, even when approved later. '
          'New quotes after the offer closes: LKR 5,000 registration and LKR 10,000 annual renewal. '
          'No commission, per-trip charge or trip quota.'),
        if (widget.admin && data.paymentStatus == 'verified') _button('activate_membership', 'Activate membership', () => _action('activate_membership', 'Activate driver membership', {},
          explanation: 'The server will recheck identity and payments, assign the next official registration number, '
            'and honor the stored quote entitlement atomically. Confirm this account is ready for activation.'), allowed: data.canActivate),
      ]),
      AppInfoCard(children: [const AppSectionHeader('Account status controls'), _fields({'Account status': data.accountStatus}),
        if (widget.admin) Wrap(spacing: 8, runSpacing: 8, children: [for (final status in ['active', 'inactive', 'suspended'])
          _button('account_$status', 'Set account $status', () => _action('set_account_status', 'Set account $status', {'accountStatus': status},
            explanation: 'This is a manual account decision. It does not change identity, payments, membership, ratings or trip history.'),
            allowed: data.accountStatus != status)]),
      ]),
      if (widget.admin) ...[
        const AppSectionHeader('Admin history'),
        if (_history.isEmpty) const Text('No Stage 11D admin actions recorded.'),
        ..._history.map((event) => AppInfoCard(children: [
          Text(event.text('action')), Text('Actor: ${event.text('actorUid')}'),
          Text('Previous: ${jsonEncode(event.data['previousValue'], toEncodable: DriverAdministration.display)}'),
          Text('New: ${jsonEncode(event.data['newValue'], toEncodable: DriverAdministration.display)}'),
          Text('Reason: ${event.text('reason', 'None')}'), Text(DriverAdministration.display(event.data['createdAt'])),
        ])),
        if (_moreHistory) TextButton(onPressed: _saving ? null : () => _page(true), child: const Text('Load more admin history')),
      ],
      const AppSectionHeader('Recent operation results'),
      ...data.operations.map((operation) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(
        '${operation.text('action')} · ${operation.text('status')}\n${operation.text('errorMessage', '')}'))),
    ]);
  }
}

class DriverActionDialog extends StatefulWidget {
  const DriverActionDialog({super.key, required this.title, required this.fields, required this.admin, required this.explanation, this.reasonRequired = false});
  final String title, explanation;
  final Map<String, String> fields;
  final bool admin;
  final bool reasonRequired;
  @override
  State<DriverActionDialog> createState() => _DriverActionDialogState();
}
class _DriverActionDialogState extends State<DriverActionDialog> {
  final _form = GlobalKey<FormState>();
  String? _validationError;
  late final _controllers = {for (final key in widget.fields.keys) key: TextEditingController(),
    if (widget.admin) 'reason': TextEditingController()};
  @override
  void dispose() { for (final controller in _controllers.values) { controller.dispose(); } super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(title: Text(widget.title),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(key: _form, child: Column(
      mainAxisSize: MainAxisSize.min, children: [Text(widget.explanation), const SizedBox(height: 16),
        for (final entry in _controllers.entries) TextFormField(controller: entry.value,
          key: ValueKey('driver_input_${entry.key}'), maxLength: entry.key == 'reason' || entry.key.endsWith('Path') ? 500 : 120,
          decoration: InputDecoration(labelText: widget.fields[entry.key] ?? (widget.reasonRequired ? 'Reason (required)' : 'Reason (optional)')),
          validator: (value) => validateDriverActionField(entry.key, value, widget.fields[entry.key] ?? 'Reason', reasonRequired: widget.reasonRequired)),
      ])))),
    actions: [
      if (_validationError != null) Semantics(liveRegion: true, child: Text(_validationError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(key: const Key('confirm_driver_action'), onPressed: () {
        final errors = _controllers.entries.map((entry) => validateDriverActionField(entry.key, entry.value.text,
          widget.fields[entry.key] ?? 'Reason', reasonRequired: widget.reasonRequired)).whereType<String>();
        setState(() => _validationError = errors.isEmpty ? null : errors.first);
        if (_form.currentState!.validate()) {
          Navigator.pop(context, _controllers.map((key, value) => MapEntry(key, value.text.trim())));
        }
      }, child: const Text('Confirm'))]);
}
