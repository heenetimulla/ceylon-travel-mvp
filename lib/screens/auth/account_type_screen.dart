import 'package:flutter/material.dart';

import '../../core/enums/account_type.dart';
import '../../core/widgets/account_type_card.dart';
import '../admin/admin_dashboard_screen.dart';
import 'driver_registration_screen.dart';
import 'user_registration_screen.dart';

class AccountTypeScreen extends StatelessWidget {
  const AccountTypeScreen({super.key});

  void _openDashboard(BuildContext context, AccountType type) {
    Widget screen;

    switch (type) {
      case AccountType.tourist:
        screen = const UserRegistrationScreen();
        break;
      case AccountType.driver:
        screen = const DriverRegistrationScreen();
        break;
      case AccountType.admin:
        screen = const AdminDashboardScreen();
        break;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select account type')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'How will you use Ceylon Travel?',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This decides which dashboard you will see.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 22),
            AccountTypeCard(
              icon: Icons.person_pin_circle_outlined,
              title: 'Tourist / Customer',
              subtitle:
                  'Post trips, receive private driver bids, accept one bid, chat and rate.',
              onTap: () => _openDashboard(context, AccountType.tourist),
            ),
            AccountTypeCard(
              icon: Icons.local_taxi_outlined,
              title: 'Driver',
              subtitle:
                  'View open trip posts, submit private bids, complete trips and receive ratings.',
              onTap: () => _openDashboard(context, AccountType.driver),
            ),
            AccountTypeCard(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin Demo',
              subtitle:
                  'Monitor users, drivers, verifications, ratings and complaints.',
              onTap: () => _openDashboard(context, AccountType.admin),
            ),
          ],
        ),
      ),
    );
  }
}
