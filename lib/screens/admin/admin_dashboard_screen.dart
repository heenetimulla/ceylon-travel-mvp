import 'package:flutter/material.dart';

import '../shared/placeholder_dashboard.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDashboard(
      title: 'Admin Dashboard',
      subtitle:
          'Basic admin dashboard will monitor users, drivers, ratings, complaints and verifications.',
      icon: Icons.admin_panel_settings_outlined,
    );
  }
}
