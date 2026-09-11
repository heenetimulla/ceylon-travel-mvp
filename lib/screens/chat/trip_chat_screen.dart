import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../app/app_colors.dart';
import '../../app/app_text_styles.dart';
import '../../core/models/public_profile.dart';
import '../../core/models/trip_chat_message.dart';
import '../../core/models/trip_post.dart';
import '../../core/services/trip_chat_service.dart';
import '../../core/services/trip_location_service.dart';
import '../../core/widgets/app_components.dart';
import '../../core/widgets/profile_avatar.dart';

class TripChatScreen extends StatefulWidget {
  const TripChatScreen({super.key, required this.tripPost, this.actorUid, this.tripStream,
    this.messagesStream, this.profileStream, this.onSend, this.messageIdFactory, this.locationService});
  final TripPost tripPost;
  // Injectable data/operations for focused widget tests; production uses authenticated services.
  final String? actorUid;
  final Stream<TripPost>? tripStream;
  final Stream<List<TripChatMessage>>? messagesStream;
  final Stream<PublicProfile?>? profileStream;
  final Future<void> Function(TripChatMessage)? onSend;
  final String Function()? messageIdFactory;
  final TripLocationService? locationService;
  @override
  State<TripChatScreen> createState() => _TripChatScreenState();
}

class _TripChatScreenState extends State<TripChatScreen> {
  late final _service = TripChatService();
  late final _actor = widget.actorUid ?? _service.uid;
  late final _location = widget.locationService ?? TripLocationService();
  final _text = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<TripPost>? _tripSubscription;
  StreamSubscription<List<TripChatMessage>>? _messageSubscription;
  Stream<PublicProfile?>? _profile;
  TripPost? _trip;
  List<TripChatMessage> _messages = [];
  TripChatMessage? _pending;
  String? _otherUid, _actionError, _pendingDriver;
  bool _tripFailed = false, _messagesFailed = false, _messagesReady = false;
  bool _busy = false, _newMessages = false;
  int _messageGeneration = 0;

  bool get _writable => _trip != null && !_tripFailed && !_messagesFailed &&
    _messagesReady && TripChatMessage.canWrite(_trip!, _actor);

  @override
  void initState() { super.initState(); _subscribeTrip(); }
  void _subscribeTrip() {
    _tripSubscription?.cancel();
    try {
    _tripSubscription = (widget.tripStream ?? _service.watchTrip(widget.tripPost.id)).listen((trip) {
      if (!mounted) return;
      if (!TripChatMessage.canRead(trip, _actor)) { _loseAccess(); return; }
      final otherUid = trip.creatorId == _actor ? trip.acceptedDriverId : trip.creatorId;
      final assignmentChanged = _trip?.acceptedDriverId != trip.acceptedDriverId;
      setState(() {
        _trip = trip;
        _tripFailed = false;
        if (assignmentChanged) { _pending = null; _pendingDriver = null; _text.clear(); }
        if (_otherUid != otherUid) {
          _otherUid = otherUid;
          _profile = otherUid == null ? null : widget.profileStream ?? FirebaseFirestore.instance.collection('user_public_profiles').doc(otherUid)
            .snapshots().map((doc) => doc.exists ? PublicProfile.fromMap(doc.data()!) : null);
        }
      });
      // The creator's query spans all assignments, including a reopened trip.
      if (_messageSubscription == null || (assignmentChanged && _actor != trip.creatorId)) _subscribeMessages();
    }, onError: (_) => _loseAccess());
    } catch (_) { _loseAccess(); }
  }
  void _loseAccess() {
    if (!mounted) return;
    _messageGeneration++;
    _messageSubscription?.cancel();
    _messageSubscription = null;
    setState(() {
      _trip = null; _tripFailed = true; _messages = []; _pending = null; _pendingDriver = null;
      _text.clear(); _profile = null; _otherUid = null;
    });
  }
  void _subscribeMessages() {
    final trip = _trip;
    if (trip == null) return;
    _messageSubscription?.cancel();
    final generation = ++_messageGeneration;
    setState(() { _messagesReady = false; _messagesFailed = false; _messages = []; });
    try {
    _messageSubscription = (widget.messagesStream ?? _service.watchMessages(trip)).listen((messages) {
      if (!mounted || generation != _messageGeneration) return;
      final visible = messages.where((message) => message.isVisibleTo(trip.creatorId, _actor)).toList();
      final latest = !_scroll.hasClients || _scroll.offset < 100 || _messages.isEmpty;
      final changed = visible.length != _messages.length ||
        (visible.isNotEmpty && (_messages.isEmpty || visible.last.id != _messages.last.id));
      setState(() {
        _messages = visible; _messagesReady = true; _messagesFailed = false;
        if (changed && !latest) _newMessages = true;
      });
      if (latest) _showLatest();
    }, onError: (_) {
      if (mounted && generation == _messageGeneration) {
        setState(() { _messagesFailed = true; _messages = []; });
      }
    });
    } catch (_) {
      if (mounted) setState(() => _messagesFailed = true);
    }
  }
  void _showLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(0);
      if (_newMessages) setState(() => _newMessages = false);
    });
  }
  String _newId() => widget.messageIdFactory?.call() ?? _service.newMessageId(widget.tripPost.id);
  TripChatMessage _draft({String? text, TripCoordinates? coordinates}) => TripChatMessage(
    id: _newId(), tripId: widget.tripPost.id, senderId: _actor,
    senderRole: _actor == _trip!.creatorId ? 'creator' : 'driver',
    assignmentDriverId: _trip!.acceptedDriverId!,
    messageType: coordinates == null ? 'text' : 'location', text: text,
    latitude: coordinates?.latitude, longitude: coordinates?.longitude);

  Future<void> _sendText() async {
    if (!_writable || _busy || _pending != null) return;
    try {
      final text = TripChatMessage.validateText(_text.text);
      _pending = _draft(text: text);
      _pendingDriver = _trip!.acceptedDriverId;
      await _deliverPending();
    } on ArgumentError catch (error) {
      setState(() => _actionError = error.message.toString());
    } catch (_) {
      if (mounted) setState(() => _actionError = 'Could not prepare your message. Please try again.');
    }
  }
  Future<void> _shareLocation() async {
    if (!_writable || _busy || _pending != null) return;
    final driver = _trip!.acceptedDriverId;
    setState(() { _busy = true; _actionError = null; });
    try {
      final coordinates = await _location.currentCoordinates();
      // The trip may have completed/reopened while the OS permission dialog was open.
      if (!mounted) return;
      if (!_writable || _trip!.acceptedDriverId != driver) {
        setState(() => _actionError = 'The trip changed. No location was sent.');
        return;
      }
      _pending = _draft(coordinates: coordinates);
      _pendingDriver = driver;
    } on TripLocationException catch (error) {
      if (mounted) setState(() => _actionError = error.message);
    } catch (_) {
      if (mounted) setState(() => _actionError = 'Could not share your location. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _pending != null) await _deliverPending();
  }
  Future<void> _deliverPending() async {
    final pending = _pending;
    final expectedDriver = _pendingDriver;
    if (pending == null || !_writable || _busy) return;
    setState(() { _busy = true; _actionError = null; });
    try {
      if (widget.onSend == null && _service.uid != _actor) throw StateError('Your session changed.');
      if (widget.onSend != null) {
        await widget.onSend!(pending);
      } else if (pending.messageType == 'text') {
        await _service.sendText(tripId: pending.tripId, messageId: pending.id, text: pending.text!, expectedAcceptedDriverId: expectedDriver);
      } else {
        await _service.sendLocation(tripId: pending.tripId, messageId: pending.id,
          latitude: pending.latitude!, longitude: pending.longitude!, expectedAcceptedDriverId: expectedDriver);
      }
      if (!mounted) return;
      if (_pending == pending) {
        setState(() { _pending = null; _pendingDriver = null; if (pending.messageType == 'text') _text.clear(); });
      }
      _showLatest();
    } catch (_) {
      if (mounted) setState(() => _actionError = 'Could not confirm delivery. Check your connection, then retry this message safely.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _openMaps(TripChatMessage message) async {
    try {
      await _location.openMaps(TripCoordinates(message.latitude!, message.longitude!));
    } on TripLocationException catch (error) {
      if (mounted) setState(() => _actionError = error.message);
    }
  }
  @override
  void dispose() {
    _tripSubscription?.cancel(); _messageSubscription?.cancel();
    _text.dispose(); _scroll.dispose(); super.dispose();
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageAppBar(title: Text('Trip Chat')),
    body: SafeArea(child: _trip == null
      ? Center(child: _tripFailed ? Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This chat is unavailable. The trip or your access may have changed.'),
          TextButton(onPressed: _subscribeTrip, child: const Text('Retry')),
        ]) : const CircularProgressIndicator())
      : Padding(padding: EdgeInsets.symmetric(horizontal: appPagePadding(context).left),
          child: LayoutBuilder(builder: (context, constraints) {
            final content = _content(context);
            // Keep the composer reachable on short screens/landscape with a keyboard.
            return constraints.maxHeight < 320
              ? SingleChildScrollView(child: SizedBox(height: 420, child: content)) : content;
          }))),
  );
  Widget _content(BuildContext context) => Column(children: [
    Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Trip: ${_trip!.referenceLabel}', style: AppTextStyles.caption),
      const SizedBox(height: 6),
      StreamBuilder<PublicProfile?>(key: ValueKey(_otherUid), stream: _profile, builder: (context, snapshot) {
        final name = snapshot.hasError ? '' : snapshot.data?.fullName ?? '';
        return Row(children: [ProfileAvatar(fullName: name, profilePhotoPath: snapshot.data?.profilePhotoPath),
          const SizedBox(width: 12), Expanded(child: Text(name.isNotEmpty ? name : 'Participant profile unavailable',
            style: AppTextStyles.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis))]);
      }),
    ])),
    Expanded(child: _messagesFailed ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Could not load messages. Check your connection.'),
      TextButton(onPressed: _subscribeMessages, child: const Text('Retry Messages')),
    ])) : !_messagesReady ? const Center(child: CircularProgressIndicator())
      : _messages.isEmpty ? const Center(child: Text('No messages yet. Use this private chat to coordinate your trip.'))
      : ListView.builder(key: const Key('trip_chat_messages'), controller: _scroll, reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 8), itemCount: _messages.length,
          itemBuilder: (context, index) {
            // Firestore emits ascending order; reverse layout keeps newest at the bottom.
            final message = _messages[_messages.length - 1 - index];
            return _ChatBubble(key: ValueKey(message.id), message: message,
              isMe: message.senderId == _actor, onOpenMaps: () => _openMaps(message));
          })),
    if (_newMessages) TextButton(onPressed: _showLatest, child: const Text('New messages')),
    if (_actionError != null) Padding(padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(_actionError!, style: AppTextStyles.secondary, maxLines: 3, overflow: TextOverflow.ellipsis)),
    if (!TripChatMessage.canWrite(_trip!, _actor))
      const Padding(padding: EdgeInsets.all(12), child: Text('Chat history is read-only.'))
    else Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(children: [
      TextField(key: const Key('trip_chat_text'), controller: _text, enabled: _writable && !_busy && _pending == null,
        minLines: 1, maxLines: 3, maxLength: 1000,
        decoration: const InputDecoration(labelText: 'Message', counterText: '')),
      const SizedBox(height: 6),
      if (_pending != null && !_busy)
        FilledButton(key: const Key('trip_chat_retry_send'), onPressed: _writable ? _deliverPending : null,
          child: const Text('Retry Message'))
      else Wrap(spacing: 12, runSpacing: 4, children: [
        OutlinedButton.icon(key: const Key('trip_chat_share_location'),
          onPressed: _writable && !_busy ? _shareLocation : null,
          icon: const Icon(Icons.my_location_outlined), label: const Text('Share Location')),
        FilledButton(key: const Key('trip_chat_send'), onPressed: _writable && !_busy ? _sendText : null,
          child: Text(_busy ? 'Please wait...' : 'Send')),
      ]),
    ])),
  ]);
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({super.key, required this.message, required this.isMe, required this.onOpenMaps});
  final TripChatMessage message;
  final bool isMe;
  final VoidCallback onOpenMaps;
  @override
  Widget build(BuildContext context) {
    if (!message.isValid) return const Padding(padding: EdgeInsets.all(8), child: Text('Message unavailable'));
    final time = message.createdAt;
    final timestamp = time == null ? 'Sending...' : '${MaterialLocalizations.of(context).formatShortDate(time.toLocal())} '
      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(time.toLocal()))}';
    return Align(alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: Card(
        color: isMe ? AppColors.softBlue : AppColors.surface,
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${message.senderRole == 'driver' ? 'Driver' : 'Creator'}${isMe ? ' · You' : ''}', style: AppTextStyles.caption),
          const SizedBox(height: 6),
          if (message.messageType == 'location') ...[
            const Wrap(spacing: 6, children: [Icon(Icons.location_on_outlined), Text('Location shared')]),
            TextButton(onPressed: onOpenMaps, child: const Text('Open in Maps')),
          ] else Text(message.text!, style: AppTextStyles.body),
          const SizedBox(height: 6), Text(timestamp, style: AppTextStyles.caption),
        ])),
      )));
  }
}
