import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/driver_evidence_service.dart';
import '../services/evidence_image_service.dart';

class DriverEvidenceUpload extends StatefulWidget {
  const DriverEvidenceUpload({super.key, required this.uid, required this.revision, required this.type,
    required this.enabled, required this.onChange, required this.onState, this.service, this.images});
  final String uid;
  final int revision;
  final EvidenceType type;
  final bool enabled;
  final void Function(String?) onChange;
  final void Function(bool busy, bool ready) onState;
  final DriverEvidenceService? service;
  final EvidenceImageService? images;
  @override
  State<DriverEvidenceUpload> createState() => _DriverEvidenceUploadState();
}

class _DriverEvidenceUploadState extends State<DriverEvidenceUpload> {
  late final _service = widget.service ?? DriverEvidenceService();
  late final _images = widget.images ?? const EvidenceImageService();
  PreparedEvidenceImage? _image;
  String? _name, _error, _path;
  bool _busy = false, _readable = false;
  double? _progress;
  final _preview = _EvidencePreview();

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _choose({bool camera = false}) async {
    setState(() { _busy = true; _error = null; _progress = null; });
    widget.onState(true, false);
    try {
      final selected = await _service.selectFor(widget.type, camera: camera);
      if (!mounted) { return; }
      if (selected == null) { return; }
      // Allow the preparing indicator to paint before web's local codec work.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final prepared = await _images.prepare(selected.bytes, selected.name, widget.type);
      if (!mounted) { return; }
      setState(() { _image = prepared; _name = selected.name; _readable = false; _path = null; });
      widget.onChange(null);
    } on EvidenceImageException catch (e) {
      if (mounted) { setState(() => _error = e.message); }
    } catch (_) {
      if (mounted) { setState(() => _error = 'Could not prepare this photo. Please choose another photo.'); }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onState(false, _image == null || _path != null);
      }
    }
  }

  Future<void> _upload() async {
    if (_image == null || !_readable || _busy) { return; }
    setState(() { _busy = true; _error = null; _progress = 0; });
    widget.onState(true, false);
    try {
      final path = await _service.upload(widget.uid, widget.revision, widget.type, _image!, (progress) {
        if (mounted) { setState(() => _progress = progress); }
      });
      if (!mounted) { return; }
      setState(() => _path = path);
      widget.onChange(path);
    } catch (_) {
      if (mounted) { setState(() => _error = 'Photo upload failed. Check your connection and retry, or refresh if your application changed.'); }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onState(false, _path != null);
      }
    }
  }

  void _remove() {
    setState(() { _image = null; _name = null; _path = null; _error = null; _readable = false; });
    widget.onChange(null);
    widget.onState(false, true);
  }

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.type.label, style: Theme.of(context).textTheme.titleSmall),
      Text(widget.type == EvidenceType.selfie
        ? 'Take a clear selfie using your device camera. Make sure your face is clearly visible, then press Upload.'
        : widget.type == EvidenceType.paymentSlip
          ? 'Take a photo or select a clear image of your payment slip, then press Upload.'
          : 'Select a clear image. Make sure all details are readable, then press Upload.'),
      if (widget.type == EvidenceType.selfie && !_service.mobileCapture)
        const Text('On web/desktop, select a recently taken selfie. Direct camera capture is not available here.'),
      if (_name != null) Text(_name!, maxLines: 2, overflow: TextOverflow.ellipsis),
      if (_image != null) ...[
        SizedBox(height: 180, child: Image.memory(_image!.bytes, fit: BoxFit.contain)),
        TextButton(onPressed: _busy ? null : () => _preview.show(context, _image!.bytes, widget.type.label),
          child: const Text('Inspect photo')),
        if (_path == null) CheckboxListTile(contentPadding: EdgeInsets.zero, value: _readable,
          onChanged: widget.enabled && !_busy ? (value) => setState(() => _readable = value ?? false) : null,
          title: Text(widget.type == EvidenceType.selfie ? 'My face is clear and recognizable.' : 'I can read every detail clearly.'),
          subtitle: const Text('Zoom in to check. If unclear, remove this photo and choose another.')),
      ],
      if (_busy) ...[
        Text(_progress == null ? 'Preparing image...' : 'Uploading photo...'),
        LinearProgressIndicator(value: _progress),
      ],
      if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_path != null) Text(widget.type == EvidenceType.paymentSlip
        ? 'Uploaded — ready to submit your payment claim' : 'Uploaded — ready to submit with your identity details'),
      Wrap(spacing: 8, children: [
        OutlinedButton(key: ValueKey('choose_${widget.type.stored}'), onPressed: widget.enabled && !_busy ? _choose : null,
          child: Text(widget.type == EvidenceType.selfie && _service.mobileCapture
            ? (_image == null ? 'Take selfie' : 'Retake selfie') : _service.mobileCapture ? 'Choose from gallery' : (_image == null ? 'Choose photo' : 'Replace photo'))),
        if (widget.type != EvidenceType.selfie && _service.mobileCapture)
          OutlinedButton(onPressed: widget.enabled && !_busy ? () => _choose(camera: true) : null, child: const Text('Take photo')),
        if (_image != null) TextButton(onPressed: widget.enabled && !_busy ? _remove : null, child: const Text('Remove photo')),
        if (_image != null && _path == null) FilledButton(key: ValueKey('upload_${widget.type.stored}'),
          onPressed: widget.enabled && !_busy && _readable ? _upload : null, child: const Text('Upload photo')),
      ]),
    ]));
}

// Close private image routes when their owning, authorization-gated panel leaves.
class _EvidencePreview {
  DialogRoute<void>? _route;
  NavigatorState? _navigator;
  Future<void> show(BuildContext context, Uint8List bytes, String title) async {
    if (_route != null) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(context: context,
      builder: (context) => Dialog(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Padding(padding: const EdgeInsets.all(12), child: Text(title)),
    SizedBox(height: MediaQuery.sizeOf(context).height * .65, width: MediaQuery.sizeOf(context).width * .9,
      child: InteractiveViewer(minScale: 1, maxScale: 5, child: Image.memory(bytes, fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Text('This photo cannot be displayed. Please request another photo.')))),
    TextButton(onPressed: () {
      Navigator.pop(context);
    }, child: const Text('Close')),
    ])));
    _route = route;
    _navigator = navigator;
    try {
      final closed = navigator.push(route);
      await closed;
    }
    finally { if (identical(_route, route)) { _route = null; _navigator = null; } }
  }

  void dispose() {
    final route = _route, navigator = _navigator;
    _route = null;
    _navigator = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route != null && navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }
}

class DriverEvidenceReview extends StatefulWidget {
  const DriverEvidenceReview({super.key, required this.uid, required this.evidence, this.service});
  final String uid;
  final List<dynamic> evidence;
  final DriverEvidenceService? service;
  @override
  State<DriverEvidenceReview> createState() => _DriverEvidenceReviewState();
}
class _DriverEvidenceReviewState extends State<DriverEvidenceReview> {
  int _generation = 0;
  bool _busy = false;
  String? _error;
  final _preview = _EvidencePreview();
  @override
  void dispose() {
    _generation++; _preview.dispose(); super.dispose();
  }
  @override
  void didUpdateWidget(covariant DriverEvidenceReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid || oldWidget.service != widget.service) {
      _generation++; _preview.dispose(); _busy = false; _error = null;
    }
  }
  Future<void> _view(String path, String label) async {
    final generation = ++_generation;
    final service = widget.service ?? DriverEvidenceService();
    setState(() { _busy = true; _error = null; });
    try {
      final bytes = await service.review(widget.uid, path);
      if (!mounted || generation != _generation) {
        return;
      }
      await _preview.show(context, bytes, label);
    } catch (error) {
      if (mounted && generation == _generation) { setState(() => _error = DriverEvidenceService.reviewError(error)); }
    } finally { if (mounted && generation == _generation) { setState(() => _busy = false); } }
  }
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (_busy) const LinearProgressIndicator(),
    if (_error != null) Text(_error!),
    if (widget.evidence.whereType<Map>().any((record) => record['storagePath'] is! String ||
        !DriverEvidenceService.validPath(widget.uid, record['storagePath'] as String)))
      Text('Invalid private photo reference. Refresh this record or contact support.', style: TextStyle(color: Theme.of(context).colorScheme.error)),
    for (final record in widget.evidence.whereType<Map>())
      if (record['storagePath'] is String && DriverEvidenceService.validPath(widget.uid, record['storagePath'] as String))
        OutlinedButton(onPressed: _busy ? null : () => _view(record['storagePath'] as String, '${record['evidenceType']}'),
          child: Text(record['evidenceType'] == 'payment_slip' ? 'View payment slip privately' : 'View privately: ${record['evidenceType']} (${record['width']} × ${record['height']})')),
  ]);
}
