import 'package:flutter/material.dart';
import '../services/admin_service.dart';

class AdminAccessGate extends StatefulWidget {
  const AdminAccessGate({super.key, required this.service, required this.builder, this.hideWhenDenied = false});
  final AdminService service;
  final Widget Function(BuildContext, String) builder;
  final bool hideWhenDenied;
  @override
  State<AdminAccessGate> createState() => _AdminAccessGateState();
}

class _AdminAccessGateState extends State<AdminAccessGate> {
  late Stream<AdminAccess> _access = widget.service.watchAccess();
  @override
  Widget build(BuildContext context) => StreamBuilder<AdminAccess>(
    stream: _access,
    builder: (context, snapshot) {
      final access = snapshot.hasError ? const AdminAccess(AdminAccessStatus.error)
        : snapshot.data ?? const AdminAccess(AdminAccessStatus.loading);
      if (access.status == AdminAccessStatus.allowed && access.uid != null) {
        return KeyedSubtree(key: ValueKey(access.uid), child: widget.builder(context, access.uid!));
      }
      if (widget.hideWhenDenied) return const SizedBox.shrink();
      if (access.status == AdminAccessStatus.loading) {
        return const Center(child: CircularProgressIndicator(semanticsLabel: 'Checking admin access'));
      }
      final message = switch (access.status) {
        AdminAccessStatus.signedOut => 'Please sign in to access the admin dashboard.',
        AdminAccessStatus.error => 'Could not verify admin access. Please try again.',
        _ => 'Access denied. An administrator account is required.',
      };
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 36), const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: () async {
            // Replace the gate immediately so no old dashboard remains visible.
            setState(() => _access = Stream<AdminAccess>.value(const AdminAccess(AdminAccessStatus.loading)));
            await widget.service.readAccess(forceRefresh: true);
            if (mounted) setState(() => _access = widget.service.watchAccess());
          }, child: const Text('Check access again')),
        ],
      )));
    },
  );
}
