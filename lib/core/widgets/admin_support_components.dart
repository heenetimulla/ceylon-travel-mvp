import 'package:flutter/material.dart';
import '../services/admin_support_service.dart';
import 'admin_access_gate.dart';

String adminSupportDate(BuildContext context, DateTime? value) {
  if (value == null) return 'Not available';
  final local = value.toLocal(), format = MaterialLocalizations.of(context);
  return '${format.formatFullDate(local)} ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

class AdminSupportGate extends StatelessWidget {
  const AdminSupportGate({super.key, required this.service, required this.builder, this.hideWhenDenied = false});
  final AdminSupportService service;
  final Widget Function(BuildContext, String) builder;
  final bool hideWhenDenied;
  @override
  Widget build(BuildContext context) => AdminAccessGate(service: service, builder: builder,
    hideWhenDenied: hideWhenDenied,
    deniedMessage: 'Access denied. Support staff permission is required.',
    signedOutMessage: 'Please sign in to access support management.');
}
