import 'package:flutter/material.dart';

import '../shared/placeholder_dashboard.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDashboard(
      title: 'Driver Dashboard',
      subtitle:
          'Next we will add driver registration, NIC upload placeholder and open trip posts.',
      icon: Icons.local_taxi_outlined,
    );
  }
}
