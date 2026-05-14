import 'package:flutter/material.dart';

import '../../core/enums/account_type.dart';
import '../../core/widgets/upload_placeholder.dart';
import '../driver/driver_home_screen.dart';
import '../tourist/tourist_home_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    this.initialAccountType = AccountType.tourist,
  });

  final AccountType initialAccountType;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController fullNameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController cityController = TextEditingController();
  final TextEditingController vehicleTypeController = TextEditingController();
  final TextEditingController vehicleNumberController = TextEditingController();
  final TextEditingController operatingAreaController = TextEditingController();
  final TextEditingController availableAreasController =
      TextEditingController();

  late AccountType selectedAccountType;

  bool get isDriver => selectedAccountType == AccountType.driver;

  @override
  void initState() {
    super.initState();
    selectedAccountType = widget.initialAccountType == AccountType.driver
        ? AccountType.driver
        : AccountType.tourist;
  }

  @override
  void dispose() {
    fullNameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    cityController.dispose();
    vehicleTypeController.dispose();
    vehicleNumberController.dispose();
    operatingAreaController.dispose();
    availableAreasController.dispose();
    super.dispose();
  }

  void _selectAccountType(AccountType accountType) {
    setState(() {
      selectedAccountType = accountType;
    });
  }

  void _createAccount() {
    final Widget destination = isDriver
        ? const DriverHomeScreen()
        : const TouristHomeScreen();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create your account',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use one registration form for tourist/user and driver accounts. Firebase saving will be connected in Week 3.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email optional',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password',
                      prefixIcon: Icon(Icons.lock_reset_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cityController,
                    decoration: const InputDecoration(
                      labelText: 'City / District',
                      prefixIcon: Icon(Icons.location_city_outlined),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Account type selector',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ChoiceChip(
                        key: const Key('touristAccountTypeChip'),
                        label: const Text('Tourist/User'),
                        selected: selectedAccountType == AccountType.tourist,
                        onSelected: (_) =>
                            _selectAccountType(AccountType.tourist),
                      ),
                      ChoiceChip(
                        key: const Key('driverAccountTypeChip'),
                        label: const Text('Driver'),
                        selected: selectedAccountType == AccountType.driver,
                        onSelected: (_) =>
                            _selectAccountType(AccountType.driver),
                      ),
                    ],
                  ),
                  if (isDriver) ...[
                    const SizedBox(height: 22),
                    TextField(
                      controller: vehicleTypeController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle type',
                        hintText: 'Car / Van / SUV',
                        prefixIcon: Icon(Icons.directions_car_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: vehicleNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle number',
                        prefixIcon: Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: operatingAreaController,
                      decoration: const InputDecoration(
                        labelText: 'Operating area',
                        prefixIcon: Icon(Icons.map_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: availableAreasController,
                      decoration: const InputDecoration(
                        labelText: 'Available areas',
                        prefixIcon: Icon(Icons.route_outlined),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const UploadPlaceholder(
                      title: 'NIC / ID upload placeholder',
                      subtitle: 'Will upload to Firebase Storage later',
                      icon: Icons.badge_outlined,
                    ),
                    const SizedBox(height: 12),
                    const UploadPlaceholder(
                      title: 'Selfie verification placeholder',
                      subtitle: 'Will be reviewed by admin later',
                      icon: Icons.camera_alt_outlined,
                    ),
                  ],
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('createAccountButton'),
                      onPressed: _createAccount,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Create Account'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
