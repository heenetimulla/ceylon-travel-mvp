import 'package:flutter/material.dart';
import '../models/trip_post.dart';
import '../services/trip_chat_read_service.dart';

class TripChatUnreadIcon extends StatefulWidget {
  const TripChatUnreadIcon({super.key, required this.trip, this.unreadStream});
  final TripPost trip;
  final Stream<bool>? unreadStream;
  @override
  State<TripChatUnreadIcon> createState() => _TripChatUnreadIconState();
}
class _TripChatUnreadIconState extends State<TripChatUnreadIcon> {
  late Stream<bool> _unread;
  void _listen() {
    try { _unread = widget.unreadStream ?? TripChatReadService().watchUnread(widget.trip); }
    catch (_) { _unread = Stream.value(false); }
  }
  @override
  void initState() { super.initState(); _listen(); }
  @override
  void didUpdateWidget(covariant TripChatUnreadIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trip.id != widget.trip.id || oldWidget.trip.acceptedDriverId != widget.trip.acceptedDriverId ||
        oldWidget.unreadStream != widget.unreadStream) { _listen(); }
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(stream: _unread, builder: (context, snapshot) =>
    Semantics(label: snapshot.data == true && !snapshot.hasError ? 'Unread trip messages' : 'Trip chat',
      child: Badge(isLabelVisible: snapshot.data == true && !snapshot.hasError,
        backgroundColor: Colors.red, child: const Icon(Icons.chat_bubble_outline))));
}
