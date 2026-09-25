import 'package:flutter/material.dart';
import '../../core/services/driver_administration_service.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/driver_administration_panel.dart';

class DriverRegistrationStatusScreen extends StatefulWidget {
  const DriverRegistrationStatusScreen({super.key, required this.uid, this.service});
  final String uid;
  final DriverAdministrationService? service;
  @override
  State<DriverRegistrationStatusScreen> createState() => _DriverRegistrationStatusScreenState();
}
class _DriverRegistrationStatusScreenState extends State<DriverRegistrationStatusScreen> {
  late final _service = widget.service ?? DriverAdministrationService();
  late final _owner = _service.watchOwner();
  @override
  Widget build(BuildContext context) => Scaffold(appBar: const AppPageAppBar(title: Text('Driver verification & membership')),
    body: StreamBuilder<String?>(stream: _owner, builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError || snapshot.data != widget.uid) {
        return const Center(child: Text('Sign in to your driver account.'));
      }
      return ListView(padding: appPagePadding(context), children: [DriverAdministrationPanel(
        key: ValueKey(snapshot.data), uid: widget.uid, admin: false, service: _service)]);
    }));
}
