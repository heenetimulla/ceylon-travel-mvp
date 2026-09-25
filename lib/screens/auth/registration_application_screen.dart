import 'package:flutter/material.dart';
import '../../core/services/registration_application_service.dart';
import '../../core/widgets/registration_application_panel.dart';
import '../../core/widgets/app_components.dart';
import '../support/support_screens.dart';
import 'session_navigation.dart';
import 'account_screen.dart';

class RegistrationApplicationScreen extends StatefulWidget {
  const RegistrationApplicationScreen({super.key, required this.uid});
  final String uid;
  @override
  State<RegistrationApplicationScreen> createState() => _RegistrationApplicationScreenState();
}
class _RegistrationApplicationScreenState extends State<RegistrationApplicationScreen> {
  final _service = RegistrationApplicationService();
  late final _session = _service.watchSession();
  bool _checking = false;
  Future<void> _continue() async {
    setState(() => _checking = true);
    try {
      final destination = await resolveStartupSession();
      if (!mounted) { return; }
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => destination), (_) => false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to check approval. Please try again.')));
      }
    } finally {
      if (mounted) { setState(() => _checking = false); }
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Registration & verification'), actions: [LogoutButton()]),
    body: StreamBuilder<String?>(stream: _session, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) { return const Center(child: CircularProgressIndicator()); }
      if (snapshot.hasError || snapshot.data != widget.uid) { return const Center(child: Text('Sign in to view your application.')); }
      return ListView(padding: appPagePadding(context), children: [
        RegistrationApplicationPanel(key: ValueKey(widget.uid), uid: widget.uid, service: _service),
        OutlinedButton(onPressed: _checking ? null : _continue, child: const Text('Check approval and continue')),
        TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SupportFormScreen())), child: const Text('Contact support')),
        TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AccountScreen())), child: const Text('Account & Support')),
      ]);
    }));
}
