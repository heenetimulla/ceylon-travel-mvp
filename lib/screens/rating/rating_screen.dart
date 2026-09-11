import 'package:flutter/material.dart';
import '../../core/models/trip_post.dart';
import '../../core/services/rating_service.dart';
import '../../core/widgets/app_components.dart';

class RatingScreen extends StatefulWidget {
  const RatingScreen({super.key, required this.trip, required this.byCreator, this.onSubmit});
  final TripPost trip;
  final bool byCreator;
  final Future<void> Function(int stars, String comment)? onSubmit;
  @override
  State<RatingScreen> createState() => _RatingScreenState();
}
class _RatingScreenState extends State<RatingScreen> {
  final _form = GlobalKey<FormState>();
  final _comment = TextEditingController();
  int _stars = 5;
  bool _saving = false;
  String? _error;
  @override
  void dispose() { _comment.dispose(); super.dispose(); }
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      if (widget.onSubmit != null) { await widget.onSubmit!(_stars, _comment.text.trim()); }
      else { await RatingService().submit(tripId: widget.trip.id, stars: _stars, comment: _comment.text); }
      if (mounted) Navigator.pop(context);
    } catch (_) { if (mounted) setState(() => _error = 'Could not save your rating. You may already have rated this trip. Please try again.'); }
    finally { if (mounted) setState(() => _saving = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppPageAppBar(title: Text(widget.byCreator ? 'Rate your driver' : 'Rate the hire creator')),
    body: ListView(padding: appPagePadding(context), children: [
      AppInfoCard(children: [
        Text(widget.trip.referenceLabel),
        AppSectionHeader(widget.byCreator ? 'Rate your driver' : 'Rate the person who gave/created this hire'),
        Form(key: _form, child: Column(children: [
          DropdownButtonFormField<int>(initialValue: _stars, decoration: const InputDecoration(labelText: 'Stars'),
            items: [for (var i = 1; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i ${i == 1 ? 'star' : 'stars'}'))],
            onChanged: _saving ? null : (v) => setState(() => _stars = v!),
          ),
          const SizedBox(height: 16),
          TextFormField(controller: _comment, enabled: !_saving, maxLength: 1000, maxLines: 5,
            decoration: const InputDecoration(labelText: 'Written review'),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Please write a review.' : null),
          if (_error != null) Text(_error!),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving...' : 'Submit Rating')),
        ])),
      ]),
    ]),
  );
}
