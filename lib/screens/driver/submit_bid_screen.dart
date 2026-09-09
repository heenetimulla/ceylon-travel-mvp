import '../../core/widgets/app_components.dart';
import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../../core/models/trip_post.dart';
import '../../core/services/bid_service.dart';
import '../../core/widgets/info_line.dart';

class SubmitBidScreen extends StatefulWidget {
  const SubmitBidScreen({super.key, required this.tripPost});

  final TripPost tripPost;

  @override
  State<SubmitBidScreen> createState() => _SubmitBidScreenState();
}

class _SubmitBidScreenState extends State<SubmitBidScreen> {
  final TextEditingController bidPriceController = TextEditingController();
  final TextEditingController vehicleDetailsController =
      TextEditingController();
  final vehicleNumberController = TextEditingController();
  final TextEditingController hoursController = TextEditingController();
  final TextEditingController messageController = TextEditingController();

  final minutesController = TextEditingController(text: '0');
  String? vehicleType;
  bool _isSaving = false;

  @override
  void dispose() {
    bidPriceController.dispose();
    vehicleDetailsController.dispose();
    vehicleNumberController.dispose();
    hoursController.dispose();
    minutesController.dispose();
    messageController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitBid() async {
    if (_isSaving) return;
    final price = int.tryParse(bidPriceController.text.trim());
    final hours = int.tryParse(hoursController.text.trim());
    final minutes = int.tryParse(minutesController.text.trim());
    if (price == null || price <= 0 || price > 10000000) {
      _showMessage('Enter a whole-number price from LKR 1 to LKR 10,000,000.');
      return;
    }
    if (vehicleType == null) {
      _showMessage('Select the vehicle you are offering.');
      return;
    }
    if (vehicleDetailsController.text.trim().isEmpty ||
        vehicleDetailsController.text.trim().length > 160) {
      _showMessage('Enter vehicle details up to 160 characters.');
      return;
    }
    if (vehicleNumberController.text.trim().isEmpty ||
        vehicleNumberController.text.trim().length > 40) {
      _showMessage('Enter a vehicle number up to 40 characters.');
      return;
    }
    if (hours == null ||
        minutes == null ||
        hours < 0 ||
        hours > 168 ||
        minutes < 0 ||
        minutes > 59 ||
        hours * 60 + minutes < 1 ||
        hours * 60 + minutes > 10080) {
      _showMessage(
        'Enter hours and minutes for a duration from 1 minute to 7 days. Minutes must be 0 to 59.',
      );
      return;
    }
    if (messageController.text.trim().length > 500) {
      _showMessage('Keep your message within 500 characters.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await BidService().submitBid(
        tripPost: widget.tripPost,
        priceAmount: price,
        vehicleType: vehicleType!,
        vehicleDetails: vehicleDetailsController.text,
        vehicleNumber: vehicleNumberController.text,
        estimatedTripMinutes: hours * 60 + minutes,
        message: messageController.text,
      );
      if (!mounted) return;
      _showMessage('Bid submitted successfully.');
      Navigator.pop(context);
    } on BidServiceException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('Could not submit your bid. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TripPost tripPost = widget.tripPost;

    return Scaffold(
      appBar: AppPageAppBar(title: const Text('Submit Bid')),
      body: SafeArea(
        child: ListView(
          padding: appPagePadding(context),
          children: [
            Card(
              color: AppColors.surface,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Trip summary', style: AppTextStyles.section),
                    const SizedBox(height: 10),
                    Text(
                      '${tripPost.pickup} -> ${tripPost.drop}',
                      style: AppTextStyles.cardTitle,
                    ),
                    const SizedBox(height: 8),
                    InfoLine(
                      icon: Icons.calendar_month_outlined,
                      text: tripPost.dateTime,
                    ),
                    InfoLine(
                      icon: Icons.group_outlined,
                      text: tripPost.passengers,
                    ),
                    InfoLine(
                      icon: Icons.luggage_outlined,
                      text: tripPost.baggage,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            AppInfoCard(
              children: [
                const AppSectionHeader(
                  'Your offer',
                  subtitle: 'Set the price for this trip in Sri Lankan rupees.',
                ),
                TextField(
                  style: AppTextStyles.title,
                  controller: bidPriceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bid price (LKR)',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
            AppInfoCard(
              children: [
                const AppSectionHeader(
                  'Vehicle',
                  subtitle:
                      'Help the customer identify the vehicle you are offering.',
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: vehicleType,
                  decoration: const InputDecoration(labelText: 'Vehicle type'),
                  items: [
                    for (final type in BidService.vehicleTypes)
                      DropdownMenuItem(value: type, child: Text(type)),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => vehicleType = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vehicleDetailsController,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle details',
                    hintText: 'Model, make, year and color',
                    prefixIcon: Icon(Icons.directions_car_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: vehicleNumberController,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle number',
                    hintText:
                        'Registration number of the vehicle offered for this trip',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
            AppInfoCard(
              children: [
                const AppSectionHeader('Estimated trip duration'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: hoursController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Hours'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: minutesController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Minutes'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
            AppInfoCard(
              children: [
                const AppSectionHeader('Message'),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Short message',
                    hintText: 'Example: I can pick you up on time.',
                    prefixIcon: Icon(Icons.message_outlined),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSaving ? null : _submitBid,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_isSaving ? 'Submitting...' : 'Submit Bid'),
            ),
          ],
        ),
      ),
    );
  }
}
