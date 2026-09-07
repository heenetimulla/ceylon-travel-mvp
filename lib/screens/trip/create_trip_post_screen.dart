import 'package:flutter/material.dart';

import '../../core/services/trip_post_service.dart';
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
  bool _isSaving = false;

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

    if (picked == null || !mounted) return;

    setState(() {
      selectedDate = picked;
    });
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (picked == null || !mounted) return;

    setState(() {
      selectedTime = picked;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _postTripAdvertisement() async {
    if (_isSaving) return;
    if (pickupController.text.trim().isEmpty) {
      _showMessage('Enter a pickup location.');
      return;
    }
    if (dropController.text.trim().isEmpty) {
      _showMessage('Enter a drop location.');
      return;
    }
    final date = selectedDate;
    final time = selectedTime;
    if (date == null) {
      _showMessage('Select a trip date.');
      return;
    }
    if (time == null) {
      _showMessage('Select a trip time.');
      return;
    }
    final scheduledAt = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (scheduledAt.isBefore(DateTime.now())) {
      _showMessage('Choose a date and time in the future.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await TripPostService().createTripPost(
        pickupLocationText: pickupController.text,
        dropLocationText: dropController.text,
        scheduledAt: scheduledAt,
        adultsCount: adults,
        kidsCount: kids,
        baggageCount: baggage,
        vehiclePreference: vehiclePreference,
        notes: notesController.text,
      );
      if (!mounted) return;
      _showMessage('Trip / hire post created successfully.');
      Navigator.pop(context);
    } on TripPostServiceException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not save your post. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
              'Tourists can request trips and drivers can post hires for their customers. Drivers will see open posts and send private bids.',
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
                DropdownMenuItem(value: 'TukTuk', child: Text('TukTuk')),
                DropdownMenuItem(value: 'Small Car', child: Text('Small Car')),
                DropdownMenuItem(value: 'Sedan Car', child: Text('Sedan Car')),
                DropdownMenuItem(
                  value: 'Van - Highroof',
                  child: Text('Van - Highroof'),
                ),
                DropdownMenuItem(
                  value: 'Van - Flatroof',
                  child: Text('Van - Flatroof'),
                ),
                DropdownMenuItem(value: 'SUV', child: Text('SUV')),
                DropdownMenuItem(value: 'Bus', child: Text('Bus')),
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
              onPressed: _isSaving ? null : _postTripAdvertisement,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(_isSaving ? 'Saving...' : 'Post Trip / Hire'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
