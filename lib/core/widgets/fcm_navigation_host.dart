import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/trip_post.dart';
import '../services/fcm_service.dart';
import '../services/fcm_session.dart';
import '../services/workflow_notification_resolver.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/admin/admin_support_detail_screen.dart';
import '../../screens/admin/admin_user_detail_screen.dart';
import '../../screens/auth/registration_application_screen.dart';
import '../../screens/driver/driver_registration_status_screen.dart';
import '../../screens/driver/driver_home_screen.dart';
import '../../screens/tourist/tourist_home_screen.dart';
import '../../screens/support/support_screens.dart';
import '../../screens/chat/trip_chat_screen.dart';
import '../../screens/tourist/tourist_bid_list_screen.dart';
import '../../screens/trip/lifecycle_trip_screen.dart';

final notificationNavigatorKey = GlobalKey<NavigatorState>();

/// The caller must have completed authenticated server authorization first.
Widget notificationDestination(TripChatPushIntent intent, TripPost trip) {
  if (intent.type == 'trip_chat') {
    return TripChatScreen(tripPost: trip);
  }
  if (intent.opensBids) {
    return TouristBidListScreen(tripPost: trip);
  }
  return LifecycleTripScreen(tripId: trip.id);
}

Widget workflowNotificationDestination(TripChatPushIntent intent, WorkflowDestination destination) => switch (destination) {
  WorkflowDestination.supportOwner => SupportThreadScreen(requestId: intent.resourceId),
  WorkflowDestination.supportAdmin => AdminSupportDetailScreen(requestId: intent.resourceId),
  WorkflowDestination.adminApplication => AdminUserDetailScreen(uid: intent.resourceId),
  WorkflowDestination.adminPayment => AdminUserDetailScreen(uid: intent.resourceId, paymentFocus: true),
  WorkflowDestination.application => RegistrationApplicationScreen(uid: intent.resourceId),
  WorkflowDestination.driverStatus => DriverRegistrationStatusScreen(uid: intent.resourceId),
  WorkflowDestination.touristHome => const TouristHomeScreen(),
  WorkflowDestination.driverHome => const DriverHomeScreen(),
  WorkflowDestination.adminOverview => const AdminDashboardScreen(),
};

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
      if (!_fcm.isCurrentIntent(intent)) {
        return;
      }
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
  late final Future<Object> _target = widget.intent.isWorkflow
      ? FcmService.instance.loadWorkflow(widget.intent) : FcmService.instance.loadChat(widget.intent);
  bool _returningHome = false;
  Widget _fallback() {
    if (!_returningHome) {
      _returningHome = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This notification is no longer available.')));
        Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
    return const Scaffold(body: SizedBox.shrink());
  }
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(stream: _session, initialData: _auth.currentUser,
    builder: (context, session) {
      if (session.hasError || session.data?.uid != widget.intent.uid ||
          !FcmService.instance.isCurrentIntent(widget.intent)) {
        return _fallback();
      }
      return FutureBuilder<Object>(future: _target, builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _fallback();
        }
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (!FcmService.instance.isCurrentIntent(widget.intent)) {
          return _fallback();
        }
        final target = snapshot.data!;
        if (target is WorkflowDestination) {
          return workflowNotificationDestination(widget.intent, target);
        }
        if (target is! TripPost || !widget.intent.allows(_auth.currentUser?.uid, target.toFirestore())) {
          return _fallback();
        }
        return notificationDestination(widget.intent, target);
      });
    });
}
