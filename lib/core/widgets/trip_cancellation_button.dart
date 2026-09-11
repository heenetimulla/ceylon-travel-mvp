import '../../app/app_text_styles.dart';
import '../../app/app_colors.dart';
import 'package:flutter/material.dart';

import '../models/trip_cancellation.dart';
import '../models/trip_post.dart';
import '../services/trip_cancellation_service.dart';

/// Display only after the screen has verified the creator or accepted driver's
/// own bid. The service and rules independently authorize the stored trip.
class TripCancellationButton extends StatefulWidget {
  const TripCancellationButton({
    super.key,
    required this.trip,
    required this.byDriver,
    this.onCancel,
  });
  final TripPost trip;
  final bool byDriver;
  final Future<void> Function(String code, String text)? onCancel;

  @override
  State<TripCancellationButton> createState() => _TripCancellationButtonState();
}

class _TripCancellationButtonState extends State<TripCancellationButton> {
  bool _dialogOpen = false;

  Future<void> _open() async {
    if (_dialogOpen) return;
    setState(() => _dialogOpen = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final byDriver = widget.byDriver;
    final withdrawingOpenTrip = !byDriver && widget.trip.status == 'open';
    try {
      if (!byDriver) {
        final understood = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(dialogContext).colorScheme.error,
              size: 40,
            ),
            title: const Text('Cancel this trip?'),
            content: const Text(
              'This trip will be permanently cancelled and will not reopen for bidding.\n\n'
              'If you need this trip again, you will need to create a new trip post.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep Trip'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('I Understand - Continue'),
              ),
            ],
          ),
        );
        if (understood != true || !mounted) {
          return;
        }
      } else {
        final penalty = cancellationPenaltyApplies(
          widget.trip.scheduledAt,
          DateTime.now(),
        );
        final understood = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            icon: Icon(
              Icons.warning_amber_rounded,
              color: Theme.of(dialogContext).colorScheme.error,
              size: 40,
            ),
            title: const Text('Cancel this trip?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'If you cancel this trip, it will reopen for other drivers.\n\n'
                    'You will not be able to bid on this trip again.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    penalty
                        ? 'This cancellation is within 2 hours of the trip and will count toward your cancellation record.'
                        : 'No cancellation penalty will apply because the trip is more than 2 hours away.',
                    style: AppTextStyles.cardTitle,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep Trip'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('I Understand - Continue'),
              ),
            ],
          ),
        );
        if (understood != true || !mounted) {
          return;
        }
      }
      final cancelled = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _CancellationDialog(
          trip: widget.trip,
          byDriver: byDriver,
          onCancel:
              widget.onCancel ??
              (code, text) {
                final service = TripCancellationService();
                return byDriver
                    ? service.cancelByAcceptedDriver(
                        tripId: widget.trip.id,
                        reasonCode: code,
                        reasonText: text,
                      )
                    : service.cancelByCreator(
                        tripId: widget.trip.id,
                        reasonCode: code,
                        reasonText: text,
                      );
              },
        ),
      );
      if (cancelled == true && navigator.mounted) {
        if (byDriver && navigator.canPop()) navigator.pop();
        if (withdrawingOpenTrip && navigator.canPop()) {
          navigator.pop(true);
        }
        if (messenger.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                byDriver
                    ? 'Trip cancelled. The trip is open for bidding again.'
                    : 'Trip cancelled.',
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) => !widget.trip.canCancel
      ? const SizedBox.shrink()
      : OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.error,
      side: const BorderSide(color: AppColors.error),
    ),
    onPressed: _dialogOpen ? null : _open,
    icon: const Icon(Icons.cancel_outlined),
    label: const Text('Cancel Trip'),
  );
}

class _CancellationDialog extends StatefulWidget {
  const _CancellationDialog({
    required this.trip,
    required this.byDriver,
    required this.onCancel,
  });
  final TripPost trip;
  final bool byDriver;
  final Future<void> Function(String, String) onCancel;

  @override
  State<_CancellationDialog> createState() => _CancellationDialogState();
}

class _CancellationDialogState extends State<_CancellationDialog> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  String? _code;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onCancel(_code!, _text.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is TripCancellationException
              ? error.message
              : 'Could not cancel this trip. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reasons = widget.byDriver
        ? driverCancellationReasons
        : creatorCancellationReasons;
    final penalty =
        widget.trip.status == 'accepted' &&
        cancellationPenaltyApplies(widget.trip.scheduledAt, DateTime.now());
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Cancel this trip?'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.byDriver
                      ? 'If you cancel, this trip will reopen for other drivers.\nYou will not be able to bid on this trip again.'
                      : 'This trip will be closed and will not reopen for bidding.\nIf you need the trip again, you will need to create a new trip post.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Cancellation reason',
                  ),
                  items: reasons.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _code = value),
                  validator: (value) => reasons.containsKey(value)
                      ? null
                      : 'Select a cancellation reason.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _text,
                  enabled: !_saving,
                  maxLength: 500,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: _code == 'other'
                        ? 'Details (required)'
                        : 'Details (optional)',
                  ),
                  validator: (value) =>
                      validateCancellationReason(_code, value ?? '', reasons),
                ),
                const SizedBox(height: 12),
                Text(
                  penalty
                      ? 'This cancellation is within 2 hours of the trip and will count toward your cancellation record.'
                      : widget.byDriver
                      ? 'No cancellation penalty will apply because the trip is more than 2 hours away.'
                      : 'No cancellation penalty will apply.',
                ),
                const SizedBox(height: 8),
                const Text(
                  'The final penalty is determined when the cancellation is saved.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: AppTextStyles.error),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Keep Trip'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.surface,
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancel Trip'),
          ),
        ],
      ),
    );
  }
}
