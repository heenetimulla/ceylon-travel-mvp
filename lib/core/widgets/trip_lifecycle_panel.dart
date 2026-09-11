import 'package:flutter/material.dart';
import '../models/trip_post.dart';
import '../models/trip_lifecycle.dart';
import 'app_components.dart';

class TripLifecyclePanel extends StatelessWidget {
  const TripLifecyclePanel({super.key, required this.trip, required this.uid,
    required this.now, required this.onAction, this.busy = false});
  final TripPost trip;
  final String uid;
  final DateTime now;
  final bool busy;
  final void Function(LifecycleAction) onAction;
  Widget _action(String title, LifecycleAction action) => FilledButton(
    onPressed: busy ? null : () => onAction(action), child: Text(title));
  @override
  Widget build(BuildContext context) {
    final creator = uid == trip.creatorId;
    final driver = uid == trip.acceptedDriverId;
    final deadline = trip.status == 'start_requested' ? trip.startAutoStartAt : trip.endAutoCompleteAt;
    final seconds = deadline == null ? 0 : deadline.difference(now).inSeconds.clamp(0, 86400);
    return AppInfoCard(children: [
      SelectableText('Trip Reference: ${trip.referenceLabel}'),
      const SizedBox(height: 12), AppStatusChip(trip.status),
      const SizedBox(height: 12),
      if (trip.status == 'accepted' && driver) _action('Start Trip', LifecycleAction.requestStart),
      if (trip.status == 'start_requested') ...[
        const Text('The driver requested trip start. The driver may leave with the passenger immediately.'),
        Text(seconds > 0 ? 'Automatic start in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}' : 'Start deadline reached. Waiting for server confirmation.'),
        if (creator && seconds > 0) _action('Confirm Start', LifecycleAction.confirmStart),
      ],
      if (trip.status == 'in_progress') ...[
        Text(trip.startMethod == 'auto_started' ? 'This trip started automatically after the confirmation window.' : 'The trip start has been confirmed.'),
        if (driver) _action('End Trip', LifecycleAction.requestEnd),
      ],
      if (trip.status == 'end_requested') ...[
        const Text('The driver requested trip completion.'),
        Text(seconds > 0 ? 'Automatic completion in ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}' : 'Completion deadline reached. Waiting for server confirmation.'),
        if (creator && seconds > 0) _action('Confirm End', LifecycleAction.confirmEnd),
      ],
      if (trip.startedAt != null) Text('Started: ${trip.startedAt!.toLocal()}'),
      if (trip.status == 'completed') ...[
        Text(trip.completionMethod == 'auto_completed' ? 'Trip completed automatically.' : 'Completion confirmed by the hire creator.'),
        if (trip.endedAt != null) Text('Completed: ${trip.endedAt!.toLocal()}'),
      ],
    ]);
  }
}
