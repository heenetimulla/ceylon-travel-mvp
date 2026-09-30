import '../models/registration_application.dart';
import '../models/driver_administration.dart';
import 'fcm_session.dart';

enum WorkflowDestination { supportOwner, supportAdmin, adminApplication, adminPayment,
  application, driverStatus, touristHome, driverHome, adminOverview }

abstract interface class WorkflowNotificationReader {
  bool current(TripChatPushIntent intent);
  Future<Map<String, dynamic>> refreshedClaims();
  Future<Map<String, dynamic>?> read(String path);
}

/// Uses server reads supplied by FcmService, independent of widgets/plugins in tests.
class WorkflowNotificationResolver {
  const WorkflowNotificationResolver(this.reader);
  final WorkflowNotificationReader reader;

  void _checkSession(TripChatPushIntent intent) {
    if (!reader.current(intent)) {
      throw StateError('Notification session changed');
    }
  }
  Future<Map<String, dynamic>?> _read(TripChatPushIntent intent, String path) async {
    _checkSession(intent);
    final value = await reader.read(path);
    _checkSession(intent);
    return value;
  }
  Future<Map<String, dynamic>> _claims(TripChatPushIntent intent) async {
    _checkSession(intent);
    final claims = await reader.refreshedClaims();
    _checkSession(intent);
    return claims;
  }

  Future<WorkflowDestination> resolve(TripChatPushIntent intent) async {
    if (!intent.isWorkflow || !reader.current(intent)) {
      throw StateError('Notification session changed');
    }
    final claims = await _claims(intent);
    if (!reader.current(intent)) {
      throw StateError('Notification session changed');
    }
    final result = await _resolve(intent, claims);
    // Recheck authorization after the reads, including a revoke during loading.
    final latest = await _claims(intent);
    if (!reader.current(intent) ||
        (result == WorkflowDestination.supportAdmin && latest['supportAdmin'] != true) ||
        ([WorkflowDestination.adminApplication, WorkflowDestination.adminPayment,
          WorkflowDestination.adminOverview].contains(result) && latest['admin'] != true)) {
      throw StateError('Notification access changed');
    }
    return result;
  }

  Future<WorkflowDestination> _resolve(TripChatPushIntent intent, Map<String, dynamic> claims) async {
    if (intent.isSupport) {
      final staff = intent.type != 'support_admin_reply';
      if (staff && claims['supportAdmin'] != true) {
        throw StateError('Support access required');
      }
      final request = await _read(intent, 'support_requests/${intent.resourceId}');
      if (request == null || request['id'] != intent.resourceId ||
          (!staff && request['userId'] != intent.uid)) {
        throw StateError('Support request unavailable');
      }
      return staff ? WorkflowDestination.supportAdmin : WorkflowDestination.supportOwner;
    }
    if (intent.type == 'founding_offer_closed') {
      if (claims['admin'] != true) {
        throw StateError('Admin access required');
      }
      final event = await _read(intent, 'admin_notifications/founding_offer_closed');
      if (event?['type'] != 'founding_offer_closed' || event?['registrationNumber'] != 100) {
        throw StateError('Notification unavailable');
      }
      return WorkflowDestination.adminOverview;
    }
    final admin = ['registration_submitted', 'payment_submitted'].contains(intent.type);
    if (admin ? claims['admin'] != true : intent.uid != intent.resourceId) {
      throw StateError('Account access required');
    }
    final profile = await _read(intent, 'users/${intent.resourceId}');
    if (profile == null || !['tourist', 'driver'].contains(profile['accountType'])) {
      throw StateError('Account unavailable');
    }
    final application = await _read(intent, 'registration_applications/${intent.resourceId}');
    if (profile.containsKey('registrationStatus') && (application == null ||
        application['uid'] != intent.resourceId || application['applicationRevision'] != profile['applicationRevision'] ||
        application['registrationStatus'] != profile['registrationStatus'])) {
      throw StateError('Refresh application state');
    }
    if (intent.type == 'registration_submitted') {
      if (profile['registrationStatus'] != 'pending_review' || application?['registrationStatus'] != 'pending_review') {
        throw StateError('Application already reviewed');
      }
      return WorkflowDestination.adminApplication;
    }
    if (profile['accountType'] == 'driver') {
      await _read(intent, 'driver_verifications/${intent.resourceId}');
      final paymentId = profile['currentRegistrationPaymentId'];
      if (intent.isPayment && (intent.paymentId != paymentId || paymentId is! String)) {
        throw StateError('Payment changed');
      }
      Map<String, dynamic>? payment;
      if (paymentId is String && paymentId.isNotEmpty && !paymentId.contains('/')) {
        payment = await _read(intent, 'users/${intent.resourceId}/payments/$paymentId');
      }
      if (intent.isPayment && (payment == null || payment['paymentType'] != 'registration' || payment['claimSubmitted'] != true)) {
        throw StateError('Payment unavailable');
      }
      if (intent.type == 'payment_submitted') {
        if (payment?['status'] != 'pending') {
          throw StateError('Payment already reviewed');
        }
        return WorkflowDestination.adminPayment;
      }
      if (applicationOperational(profile) && driverCanBid(profile)) {
        return WorkflowDestination.driverHome;
      }
      return profile.containsKey('registrationStatus') && profile['registrationStatus'] != 'approved'
          ? WorkflowDestination.application : WorkflowDestination.driverStatus;
    }
    if (intent.isPayment || intent.type.startsWith('identity_') || intent.type == 'membership_activated') {
      throw StateError('Driver account required');
    }
    return applicationOperational(profile) ? WorkflowDestination.touristHome : WorkflowDestination.application;
  }
}
