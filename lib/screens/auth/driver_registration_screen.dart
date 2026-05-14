import 'package:flutter/material.dart';

import '../../core/enums/account_type.dart';
import 'registration_screen.dart';

class DriverRegistrationScreen extends StatelessWidget {
  const DriverRegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const RegistrationScreen(initialAccountType: AccountType.driver);
  }
}
