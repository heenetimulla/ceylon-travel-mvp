import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../firebase_options.dart';
import 'fcm_session.dart';
import '../models/trip_chat_message.dart';
import '../models/trip_post.dart';
import 'registration_application_service.dart';

@pragma('vm:entry-point')
Future<void> tripChatMessagingBackground(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Notification payloads are displayed by Android. Never display a duplicate
  // local notification here, mutate unread state, or navigate from this isolate.
}

class FcmService with WidgetsBindingObserver implements FcmTokenPort {
  FcmService._();
  static final instance = FcmService._();
  static const channelId = 'ceylon_travel_trip_chat';
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  final pendingIntent = ValueNotifier<TripChatPushIntent?>(null);
  final navigationReady = ValueNotifier<bool>(false);
  final _notifications = FlutterLocalNotificationsPlugin();
  late final FcmSession _session = FcmSession(this);
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  bool _started = false;
  bool _loggingOut = false;
  String? _observedUid;
  String? _installationId;
  SharedPreferences? _preferences;
  final _seen = <String>{};

  Future<void> initialize() async {
    if (!supported || _started) return;
    _started = true;
    try {
      _preferences = await SharedPreferences.getInstance();
      _installationId = _preferences!.getString('fcm_installation_v1');
      if (_installationId == null) {
        final random = Random.secure();
        _installationId = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
        await _preferences!.setString('fcm_installation_v1', _installationId!);
      }
      await _notifications.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_trip_chat')),
        onDidReceiveNotificationResponse: (response) {
          try {
            final data = jsonDecode(response.payload ?? '') as Map<String, dynamic>;
            // Local foreground notifications also bind to the session that displayed them.
            if (data['uid'] == _auth.currentUser?.uid) _open(data);
          } catch (_) { /* Malformed external intent: ignore. */ }
        });
      await _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(channelId, 'Trip & Chat Notifications',
          description: 'Private trip chat messages', importance: Importance.high, playSound: true));
      WidgetsBinding.instance.addObserver(this);
      _observedUid = _auth.currentUser?.uid;
      _auth.authStateChanges().listen((user) {
        if (_loggingOut && user?.uid == _observedUid && user != null) return;
        if (user?.uid != _observedUid) {
          _loggingOut = false;
          _observedUid = user?.uid;
          pendingIntent.value = null;
          _seen.clear();
          unawaited(_ignore(_notifications.cancelAll()));
        }
        unawaited(_ignore(_session.changeUser(user?.uid)));
      }, onError: (Object _) {
        pendingIntent.value = null;
        _observedUid = null;
        unawaited(_ignore(_session.changeUser(null)));
        unawaited(_ignore(_notifications.cancelAll()));
      });
      _messaging.onTokenRefresh.listen((token) {
        if (_session.uid == _auth.currentUser?.uid) unawaited(_ignore(_session.refreshToken(token)));
      }, onError: (Object _) {});
      FirebaseMessaging.onMessage.listen((message) => unawaited(_ignore(_foreground(message))));
      FirebaseMessaging.onMessageOpenedApp.listen((message) => _open(message.data));
      // Wait for persisted Firebase Auth restoration before binding a cold-start tap.
      await _auth.authStateChanges().first.timeout(const Duration(seconds: 15));
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _open(initial.data);
      final localLaunch = await _notifications.getNotificationAppLaunchDetails();
      if (localLaunch?.didNotificationLaunchApp == true) {
        try {
          final data = jsonDecode(localLaunch?.notificationResponse?.payload ?? '') as Map<String, dynamic>;
          if (data['uid'] == _auth.currentUser?.uid) _open(data);
        } catch (_) { /* Invalid payload: ignore. */ }
      }
    } catch (_) {
      // Push setup must never prevent login or the normal trip/chat experience.
    }
  }

  Future<void> _ignore(Future<void> work) async {
    try { await work; } catch (_) { /* Retry registration on app resume/login. No token logging. */ }
  }

  void _open(Map<String, dynamic> data) {
    if (_loggingOut) return;
    pendingIntent.value = TripChatPushIntent.parse(_auth.currentUser?.uid, data);
  }

  Future<TripPost> loadChat(TripChatPushIntent intent) async {
    if (_auth.currentUser?.uid != intent.uid) throw StateError('Session changed');
    final db = FirebaseFirestore.instance;
    await requireOperationalAccount(db, intent.uid).timeout(const Duration(seconds: 15));
    final snapshot = await db.collection('trip_posts').doc(intent.tripId)
      .get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 15));
    if (!snapshot.exists) throw StateError('Chat unavailable');
    final trip = TripPost.fromFirestore(snapshot);
    if (_auth.currentUser?.uid != intent.uid || !TripChatMessage.hasCurrentAssignment(trip, intent.uid)) {
      throw StateError('Chat no longer available');
    }
    return trip;
  }

  Future<void> _foreground(RemoteMessage message) async {
    final actor = _auth.currentUser?.uid;
    final intent = TripChatPushIntent.parse(actor, message.data);
    if (_loggingOut || intent == null || actor != _session.uid) return;
    // A previously queued delivery is not proof of current assignment access.
    final trip = await loadChat(intent);
    if (_auth.currentUser?.uid != actor || _session.uid != actor ||
        !TripChatMessage.hasCurrentAssignment(trip, intent.uid)) {
      return;
    }
    final key = message.messageId;
    if (key != null && !_seen.add(key)) return;
    if (_seen.length > 100) _seen.remove(_seen.first);
    // Only one foreground display path. Never use message text/profile fields.
    await _notifications.show(intent.tripId.hashCode & 0x7fffffff, 'Ceylon Travel',
      'You have a new trip message', const NotificationDetails(android: AndroidNotificationDetails(
        channelId, 'Trip & Chat Notifications', importance: Importance.high, priority: Priority.high,
        visibility: NotificationVisibility.private, icon: 'ic_stat_trip_chat')),
      payload: jsonEncode({'type': 'trip_chat', 'tripId': intent.tripId, 'uid': actor}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loggingOut) {
      unawaited(_ignore(_session.changeUser(_auth.currentUser?.uid)));
    }
  }

  DocumentReference<Map<String, dynamic>> _ref(String uid) => FirebaseFirestore.instance
      .collection('users').doc(uid).collection('fcm_tokens').doc(_installationId!);

  @override
  Future<String?> prepareToken(String uid) async {
    if (_auth.currentUser?.uid != uid) return null;
    final previous = _preferences!.getString('fcm_owner_v1');
    if (previous != null && previous != uid) {
      // Never reuse the old account's device token when deletion was unavailable
      // after an external sign-out. If rotation fails, don't register it to anyone.
      await _messaging.deleteToken().timeout(const Duration(seconds: 10));
      await _notifications.cancelAll();
    }
    var settings = await _messaging.getNotificationSettings().timeout(const Duration(seconds: 10));
    // Android 13 can report denied both before the first prompt and after denial.
    // Remember our own prompt attempt instead of assuming notDetermined is emitted.
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined ||
        (settings.authorizationStatus == AuthorizationStatus.denied &&
          _preferences!.getBool('fcm_permission_requested_v1') != true)) {
      settings = await _messaging.requestPermission(alert: true, badge: true, sound: true);
      await _preferences!.setBool('fcm_permission_requested_v1', true);
    }
    if (_auth.currentUser?.uid != uid) return null;
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      await _messaging.setAutoInitEnabled(false);
      await _ref(uid).delete().timeout(const Duration(seconds: 5));
      return null;
    }
    // Persist BEFORE fetching/saving to recover a process death during registration.
    await _preferences!.setString('fcm_owner_v1', uid);
    await _messaging.setAutoInitEnabled(true);
    return _messaging.getToken().timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> save(String uid, String token) async {
    if (_auth.currentUser?.uid != uid || _session.uid != uid || token.isEmpty || token.length > 4096 ||
        _preferences!.getString('fcm_owner_v1') != uid) {
      return;
    }
    final settings = await _messaging.getNotificationSettings().timeout(const Duration(seconds: 10));
    if (settings.authorizationStatus != AuthorizationStatus.authorized) return;
    // Reject a delayed onTokenRefresh event for a token already rotated away.
    if (await _messaging.getToken().timeout(const Duration(seconds: 10)) != token) return;
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final ref = _ref(uid);
      final old = await tx.get(ref);
      if (_auth.currentUser?.uid != uid || _session.uid != uid) return;
      tx.set(ref, {'token': token, 'platform': 'android', 'enabled': true, 'permission': 'authorized',
        'createdAt': old.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(), 'lastSeenAt': FieldValue.serverTimestamp()});
    }, timeout: const Duration(seconds: 10));
  }

  Future<void> beforeLogout(String uid) async {
    if (!_started || _installationId == null) return;
    _loggingOut = true;
    pendingIntent.value = null;
    await _ignore(_session.beforeLogout(uid).timeout(const Duration(seconds: 12)));
  }

  void logoutFailed() {
    if (!_started || _installationId == null) return;
    _loggingOut = false;
    unawaited(_ignore(_session.changeUser(_auth.currentUser?.uid)));
  }

  @override
  Future<void> detach(String uid) async {
    try {
      if (_auth.currentUser?.uid == uid) await _ref(uid).delete().timeout(const Duration(seconds: 5));
    } finally {
      await _messaging.setAutoInitEnabled(false);
      await _notifications.cancelAll();
      await _messaging.deleteToken().timeout(const Duration(seconds: 10));
      // Keep the owner marker: unexpected/offline failures trigger rotation again
      // before this installation is associated with a different signed-in account.
    }
  }
}
