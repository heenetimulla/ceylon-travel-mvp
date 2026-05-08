import 'dart:async';

import 'package:flutter/material.dart';

void main() {
  runApp(const CeylonTravelApp());
}

enum AccountType {
  tourist,
  driver,
  admin,
}

class CeylonTravelApp extends StatelessWidget {
  const CeylonTravelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ceylon Travel',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFFF6F8FA),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F766E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.travel_explore, size: 90, color: Colors.white),
            SizedBox(height: 20),
            Text(
              'Ceylon Travel',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Sri Lanka travel & driver community',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _openLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _openDemoFlow(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountTypeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                children: [
                  const SizedBox(height: 30),
                  const Icon(
                    Icons.groups_2_rounded,
                    size: 82,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Replace travel WhatsApp groups with one smart app',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tourists post trips. Drivers send private bids. Tourist accepts one bid. Then they can chat, complete the trip, and rate each other.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _openLogin(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Get Started'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _openDemoFlow(context),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('View Demo Flow'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();

  @override
  void dispose() {
    phoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

  void _continueToAccountType() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountTypeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Continue with phone',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Phone OTP will be connected with Firebase later. Email is optional for MVP, but required in the full system.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+94 77 123 4567',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email optional for MVP',
                      hintText: 'name@email.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _continueToAccountType,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Continue'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const LoginInfoCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginInfoCard extends StatelessWidget {
  const LoginInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Color(0xFF0F766E)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'MVP login is demo only. Week 3 will connect Firebase Auth, phone OTP, selfie verification, and NIC/ID upload.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
      appBar: AppBar(
        title: const Text('Select account type'),
      ),
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
              subtitle: 'Post trips, receive private driver bids, accept one bid, chat and rate.',
              onTap: () => _openDashboard(context, AccountType.tourist),
            ),
            AccountTypeCard(
              icon: Icons.local_taxi_outlined,
              title: 'Driver',
              subtitle: 'View open trip posts, submit private bids, complete trips and receive ratings.',
              onTap: () => _openDashboard(context, AccountType.driver),
            ),
            AccountTypeCard(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin Demo',
              subtitle: 'Monitor users, drivers, verifications, ratings and complaints.',
              onTap: () => _openDashboard(context, AccountType.admin),
            ),
          ],
        ),
      ),
    );
  }
}

class AccountTypeCard extends StatelessWidget {
  const AccountTypeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFE0F2F1),
                child: Icon(icon, color: const Color(0xFF0F766E), size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class UserRegistrationScreen extends StatefulWidget {
  const UserRegistrationScreen({super.key});

  @override
  State<UserRegistrationScreen> createState() => _UserRegistrationScreenState();
}

class _UserRegistrationScreenState extends State<UserRegistrationScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController cityController = TextEditingController();

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    cityController.dispose();
    super.dispose();
  }

  void _createUserAccount() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const TouristHomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Registration'),
      ),
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
                    'Create tourist/customer profile',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This is UI only. Firebase saving will be added in Week 3.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: nameController,
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
                      labelText: 'Email optional for MVP',
                      prefixIcon: Icon(Icons.email_outlined),
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
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _createUserAccount,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('Create User Account'),
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

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
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
      appBar: AppBar(
        title: const Text('Driver Registration'),
      ),
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

class UploadPlaceholder extends StatelessWidget {
  const UploadPlaceholder({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0F766E)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.upload_file),
      ),
    );
  }
}

class TouristHomeScreen extends StatelessWidget {
  const TouristHomeScreen({super.key});

  void _openCreateTripPost(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateTripPostScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tourist Dashboard'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF0F766E),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need a driver for your Sri Lanka trip?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Post your pickup, drop, passenger count, baggage, date and time. Drivers will send private bids.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF0F766E),
                  ),
                  onPressed: () => _openCreateTripPost(context),
                  child: const Text('Create Trip Post'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Example open trip posts',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const TripPostCard(
            pickup: 'Bandaranaike Airport',
            drop: 'Ella',
            dateTime: '20 May 2026 • 8:30 AM',
            passengers: '2 adults, 1 kid',
            baggage: '3 bags',
            status: 'OPEN',
          ),
          const TripPostCard(
            pickup: 'Galle Fort',
            drop: 'Mirissa',
            dateTime: '22 May 2026 • 10:00 AM',
            passengers: '4 adults',
            baggage: '2 bags',
            status: 'OPEN',
          ),
        ],
      ),
    );
  }
}

class CreateTripPostScreen extends StatefulWidget {
  const CreateTripPostScreen({super.key});

  @override
  State<CreateTripPostScreen> createState() => _CreateTripPostScreenState();
}

class _CreateTripPostScreenState extends State<CreateTripPostScreen> {
  final TextEditingController pickupController = TextEditingController();
  final TextEditingController dropController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  int adults = 1;
  int kids = 0;
  int baggage = 1;
  String vehiclePreference = 'Any';

  @override
  void dispose() {
    pickupController.dispose();
    dropController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked == null) return;

    setState(() {
      selectedDate = picked;
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked == null) return;

    setState(() {
      selectedTime = picked;
    });
  }

  void _postTripAdvertisement() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Demo trip post created. Firebase saving comes in Week 3.'),
      ),
    );

    Navigator.pop(context);
  }

  String get _dateText {
    if (selectedDate == null) return 'Select date';

    final String year = selectedDate!.year.toString();
    final String month = selectedDate!.month.toString().padLeft(2, '0');
    final String day = selectedDate!.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  String _timeText(BuildContext context) {
    if (selectedTime == null) return 'Select time';
    return selectedTime!.format(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Trip Post'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Trip advertisement',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Drivers will see this post and send private bids. Date and time must be selected from picker only.',
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: pickupController,
              decoration: const InputDecoration(
                labelText: 'Pickup location',
                hintText: 'Example: Bandaranaike Airport',
                prefixIcon: Icon(Icons.my_location_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dropController,
              decoration: const InputDecoration(
                labelText: 'Drop location',
                hintText: 'Example: Ella',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(_dateText),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickTime,
                    icon: const Icon(Icons.access_time),
                    label: Text(_timeText(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            CounterRow(
              label: 'Adults',
              value: adults,
              onMinus: () {
                if (adults <= 1) return;
                setState(() => adults--);
              },
              onPlus: () => setState(() => adults++),
            ),
            CounterRow(
              label: 'Kids',
              value: kids,
              onMinus: () {
                if (kids <= 0) return;
                setState(() => kids--);
              },
              onPlus: () => setState(() => kids++),
            ),
            CounterRow(
              label: 'Baggage',
              value: baggage,
              onMinus: () {
                if (baggage <= 0) return;
                setState(() => baggage--);
              },
              onPlus: () => setState(() => baggage++),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: vehiclePreference,
              decoration: const InputDecoration(
                labelText: 'Vehicle preference',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'Any', child: Text('Any')),
                DropdownMenuItem(value: 'Car', child: Text('Car')),
                DropdownMenuItem(value: 'Van', child: Text('Van')),
                DropdownMenuItem(value: 'SUV', child: Text('SUV')),
              ],
              onChanged: (String? value) {
                if (value == null) return;
                setState(() => vehiclePreference = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes / special request',
                hintText: 'Example: Need English-speaking driver',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _postTripAdvertisement,
              icon: const Icon(Icons.send),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Post Trip Advertisement'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CounterRow extends StatelessWidget {
  const CounterRow({
    super.key,
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: onMinus,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text(
              '$value',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: onPlus,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class TripPostCard extends StatelessWidget {
  const TripPostCard({
    super.key,
    required this.pickup,
    required this.drop,
    required this.dateTime,
    required this.passengers,
    required this.baggage,
    required this.status,
  });

  final String pickup;
  final String drop;
  final String dateTime;
  final String passengers;
  final String baggage;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Chip(
              label: Text(
                status,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
              backgroundColor: const Color(0xFFE0F2F1),
              side: BorderSide.none,
            ),
            const SizedBox(height: 8),
            Text(
              '$pickup → $drop',
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InfoLine(icon: Icons.calendar_month_outlined, text: dateTime),
            InfoLine(icon: Icons.group_outlined, text: passengers),
            InfoLine(icon: Icons.luggage_outlined, text: baggage),
          ],
        ),
      ),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({
    super.key,
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDashboard(
      title: 'Driver Dashboard',
      subtitle: 'Next we will add driver registration, NIC upload placeholder and open trip posts.',
      icon: Icons.local_taxi_outlined,
    );
  }
}

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderDashboard(
      title: 'Admin Dashboard',
      subtitle: 'Basic admin dashboard will monitor users, drivers, ratings, complaints and verifications.',
      icon: Icons.admin_panel_settings_outlined,
    );
  }
}

class PlaceholderDashboard extends StatelessWidget {
  const PlaceholderDashboard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  void _goBackToWelcome(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Back to welcome',
            onPressed: () => _goBackToWelcome(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 80, color: const Color(0xFF0F766E)),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => _goBackToWelcome(context),
                      child: const Text('Back to Welcome'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
