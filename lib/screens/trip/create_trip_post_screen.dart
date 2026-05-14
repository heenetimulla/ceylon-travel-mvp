import 'package:flutter/material.dart';

import '../../core/widgets/counter_row.dart';

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
        content: Text(
          'Demo trip or hire post created. Firebase saving comes in Week 3.',
        ),
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
      appBar: AppBar(title: const Text('Create Trip / Hire Post')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Create Trip / Hire Post',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tourists can request trips and drivers can post hires they cannot complete. Drivers will see open posts and send private bids.',
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
                child: Text('Post Trip / Hire'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
