import 'package:flutter/material.dart';

import '../../core/widgets/upload_placeholder.dart';
import '../driver/driver_home_screen.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  State<DriverRegistrationScreen> createState() =>
      _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController vehicleTypeController = TextEditingController();
  final TextEditingController vehicleNumberController = TextEditingController();
  final TextEditingController cityController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    vehicleTypeController.dispose();
    vehicleNumberController.dispose();
    cityController.dispose();
    super.dispose();
  }

  void _createDriverAccount() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Registration')),
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
                    'Create driver profile',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'NIC upload and selfie verification will be connected later.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Driver full name',
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
                    controller: cityController,
                    decoration: const InputDecoration(
                      labelText: 'City / Operating area',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const UploadPlaceholder(
                    title: 'NIC / ID upload',
                    subtitle: 'Will upload to Firebase Storage later',
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),
                  const UploadPlaceholder(
                    title: 'Selfie verification',
                    subtitle: 'Will be reviewed by admin later',
                    icon: Icons.camera_alt_outlined,
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _createDriverAccount,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Create Driver Account'),
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
