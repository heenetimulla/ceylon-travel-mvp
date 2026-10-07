import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/account_profile.dart';
import '../../core/services/profile_service.dart';
import '../../core/widgets/app_components.dart';
import 'registration_application_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key, this.service});
  final ProfileService? service;
  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  late final ProfileService _service;
  late final StreamSubscription<String?> _session;
  Future<AccountProfile>? _profile;
  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProfileService();
    if (_service.hasSession) {
      _profile = _service.load();
    }
    _session = _service.sessionChanges.listen((_) {
      if (mounted && !_service.hasSession) {
        setState(() {});
      }
    });
  }
  @override
  void dispose() {
    unawaited(_session.cancel());
    if (widget.service == null) {
      _service.dispose();
    }
    super.dispose();
  }
  void _reload() {
    final future = _service.load();
    setState(() { _profile = future; });
  }
  Future<void> _openUpgrade() async {
    final uid = _service.currentUid;
    if (uid == null) { return; }
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
      RegistrationApplicationScreen(uid: uid, upgradeRequest: true)));
    if (mounted && _service.hasSession) { _reload(); }
  }
  Future<void> _edit(AccountProfile profile, {required bool phone}) async {
    final saved = await showDialog<bool>(context: context, barrierDismissible: false,
      builder: (_) => _ProfileEditDialog(service: _service, profile: profile, phone: phone));
    if (!mounted || !_service.hasSession) {
      return;
    }
    if (saved == true) {
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(phone ? 'Phone number updated.' : 'Profile updated.')));
    }
  }
  Widget _field(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 3),
      Text(value, style: Theme.of(context).textTheme.bodyLarge),
    ]));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Profile & Account Settings')),
    body: !_service.hasSession
      ? const Center(child: Text('Sign in again to view your profile.'))
      : FutureBuilder<AccountProfile>(future: _profile, builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
              Text(profileErrorMessage(snapshot.error!)),
              TextButton(onPressed: _reload, child: const Text('Retry')),
            ])));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final profile = snapshot.data!;
        final initials = profile.fullName.split(RegExp(r'\s+')).take(2)
          .where((part) => part.isNotEmpty).map((part) => part.characters.first).join().toUpperCase();
        return ListView(padding: appPagePadding(context), children: [
          AppInfoCard(children: [
            Row(children: [CircleAvatar(radius: 28, child: Text(initials)),
              const SizedBox(width: 16), Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile.fullName, style: Theme.of(context).textTheme.titleLarge),
                  Text(profile.accountType),
                ]))]),
            const AppSectionHeader('Personal details'),
            _field('Full name', profile.fullName),
            _field('City', profile.city.isEmpty ? 'Not added' : profile.city),
            OutlinedButton.icon(onPressed: () => _edit(profile, phone: false),
              icon: const Icon(Icons.edit_outlined), label: const Text('Edit personal details')),
          ]),
          AppInfoCard(children: [
            const AppSectionHeader('Account security'),
            _field('Email · sign-in address', profile.loginEmail ?? 'Not available'),
            const Text('Your sign-in email is read-only here.'),
            const SizedBox(height: 16),
            _field('Phone number', profile.phoneNumber),
            const Text('Changing your phone number requires your current password. SMS verification is not available yet.'),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _edit(profile, phone: true),
              icon: const Icon(Icons.lock_outline), label: const Text('Change phone number')),
          ]),
          AppInfoCard(children: [
            const AppSectionHeader('Account status', subtitle: 'Managed through your application and account review.'),
            _field('Registration', profile.registrationStatus.replaceAll('_', ' ')),
            _field('Account', profile.accountStatus.replaceAll('_', ' ')),
          ]),
          if (profile.canRequestDriverUpgrade || profile.driverUpgradeStatus != null) AppInfoCard(children: [
            const AppSectionHeader('Driver / Partner upgrade'),
            if (profile.driverUpgradeStatus case final status?)
              Text(status == 'approved' ? profile.isOperationalDriver
                ? 'Driver upgrade approved — driver membership active'
                : 'Driver upgrade approved — payment/membership activation required'
                : 'Driver upgrade: ${status.replaceAll('_', ' ')}')
            else const Text('Apply using your existing account. Driver review, payment verification and membership activation are required before driving.'),
            OutlinedButton(onPressed: _openUpgrade, child: Text(profile.canRequestDriverUpgrade
              ? 'Become a Driver / Partner' : 'View driver upgrade')),
          ]),
          if (profile.isDriver) AppInfoCard(children: [
            const AppSectionHeader('Driver membership & vehicle', subtitle: 'Verification and membership details are read-only.'),
            _field('Driver registration number', profile.registrationNumber),
            _field('Identity verification', profile.value('identityVerificationStatus').replaceAll('_', ' ')),
            _field('Payment status', profile.value('paymentStatus').replaceAll('_', ' ')),
            _field('Membership plan', profile.value('membershipPlan').replaceAll('_', ' ')),
            _field('Membership status', profile.value('membershipStatus').replaceAll('_', ' ')),
            _field('Membership expiry', profile.membershipExpiry),
            _field('Vehicle type', profile.value('vehicleType')),
            _field('Vehicle number', profile.value('vehicleNumber')),
            _field('Operating area', profile.value('operatingArea')),
          ]),
        ]);
      }),
  );
}

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.service, required this.profile, required this.phone});
  final ProfileService service;
  final AccountProfile profile;
  final bool phone;
  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _city;
  final _phone = TextEditingController();
  final _password = TextEditingController();
  late final StreamSubscription<String?> _session;
  bool _busy = false;
  bool _closing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.fullName);
    _city = TextEditingController(text: widget.profile.city);
    _session = widget.service.sessionChanges.listen((_) {
      if (mounted && !widget.service.hasSession) {
        _close(false);
      }
    });
  }
  @override
  void dispose() {
    unawaited(_session.cancel());
    _name.dispose(); _city.dispose(); _phone.dispose(); _password.dispose();
    super.dispose();
  }
  void _close(bool saved) {
    if (_closing) {
      return;
    }
    _closing = true;
    Navigator.of(context).pop(saved);
  }
  Future<void> _save() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (widget.phone) {
        await widget.service.changePhone(phoneNumber: _phone.text, password: _password.text);
      } else {
        await widget.service.updateDetails(fullName: _name.text, city: _city.text);
      }
      if (mounted) {
        _close(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() { _error = profileErrorMessage(error); });
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() { _busy = false; });
      }
    }
  }
  @override
  Widget build(BuildContext context) => PopScope(canPop: !_busy, child: AlertDialog(
    title: Text(widget.phone ? 'Confirm phone number change' : 'Edit personal details'),
    content: SingleChildScrollView(child: Form(key: _form, child: Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.phone) ...[
          const Text('This replaces your account contact number. Enter your current sign-in password to confirm.'),
          const SizedBox(height: 12),
          TextFormField(key: const Key('profile_phone'), controller: _phone, enabled: !_busy,
            keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(labelText: 'New phone number'), validator: ProfileService.validatePhone),
          TextFormField(key: const Key('profile_password'), controller: _password, enabled: !_busy,
            obscureText: true, autocorrect: false, enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Current password'),
            validator: (value) => value == null || value.isEmpty ? 'Enter your current password.' : null),
        ] else ...[
          TextFormField(key: const Key('profile_name'), controller: _name, enabled: !_busy, maxLength: 120,
            decoration: const InputDecoration(labelText: 'Full name'), validator: ProfileService.validateName),
          TextFormField(key: const Key('profile_city'), controller: _city, enabled: !_busy, maxLength: 100,
            decoration: const InputDecoration(labelText: 'City (optional)'), validator: ProfileService.validateCity),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
          child: Semantics(liveRegion: true, child: Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)))),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
      ]))),
    actions: [
      TextButton(onPressed: _busy ? null : () => _close(false), child: const Text('Cancel')),
      FilledButton(onPressed: _busy ? null : _save, child: Text(widget.phone ? 'Confirm change' : 'Save changes')),
    ],
  ));
}
