import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/trip_post.dart';
import '../services/fcm_service.dart';
import '../services/fcm_session.dart';
import '../../screens/chat/trip_chat_screen.dart';

final notificationNavigatorKey = GlobalKey<NavigatorState>();

/// Defers cold-start navigation until the existing splash session routing ends.
class FcmNavigationHost extends StatefulWidget {
  const FcmNavigationHost({super.key, required this.child});
  final Widget child;
  @override
  State<FcmNavigationHost> createState() => _FcmNavigationHostState();
}

class _FcmNavigationHostState extends State<FcmNavigationHost> {
  final _fcm = FcmService.instance;
  @override
  void initState() {
    super.initState();
    _fcm.pendingIntent.addListener(_schedule);
    _fcm.navigationReady.addListener(_schedule);
    _schedule();
  }
  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_fcm.navigationReady.value) return;
      final intent = _fcm.pendingIntent.value;
      final navigator = notificationNavigatorKey.currentState;
      if (intent == null || navigator == null) return;
      _fcm.pendingIntent.value = null;
      if (FirebaseAuth.instance.currentUser?.uid != intent.uid) return;
      navigator.push(MaterialPageRoute<void>(builder: (_) => _NotificationChat(intent: intent)));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
  @override
  void dispose() {
    _fcm.pendingIntent.removeListener(_schedule);
    _fcm.navigationReady.removeListener(_schedule);
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

class _NotificationChat extends StatefulWidget {
  const _NotificationChat({required this.intent});
  final TripChatPushIntent intent;
  @override
  State<_NotificationChat> createState() => _NotificationChatState();
}

class _NotificationChatState extends State<_NotificationChat> {
  late final _auth = FirebaseAuth.instance;
  late final _session = _auth.authStateChanges();
  late final _trip = FcmService.instance.loadChat(widget.intent);
  Widget _notice(String text) => Scaffold(appBar: AppBar(title: const Text('Trip chat')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(text))));
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(stream: _session, initialData: _auth.currentUser,
    builder: (context, session) {
      if (session.hasError || session.data?.uid != widget.intent.uid) {
        return _notice('Sign in to the account that received this notification.');
      }
      return FutureBuilder<TripPost>(future: _trip, builder: (context, snapshot) {
        if (snapshot.hasError) return _notice('This chat is unavailable. Check your connection and current trip assignment.');
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return TripChatScreen(tripPost: snapshot.data!);
      });
    });
}
