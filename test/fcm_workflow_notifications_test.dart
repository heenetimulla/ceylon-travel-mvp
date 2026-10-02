import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/services/fcm_session.dart';
import 'package:taxi_app/core/services/workflow_notification_resolver.dart';
import 'package:taxi_app/core/widgets/fcm_navigation_host.dart';
import 'package:taxi_app/screens/admin/admin_user_detail_screen.dart';
import 'package:taxi_app/screens/admin/admin_support_detail_screen.dart';
import 'package:taxi_app/screens/admin/admin_dashboard_screen.dart';
import 'package:taxi_app/screens/support/support_screens.dart';
import 'package:taxi_app/screens/auth/registration_application_screen.dart';
import 'package:taxi_app/screens/driver/driver_registration_status_screen.dart';
import 'package:taxi_app/screens/driver/driver_home_screen.dart';
import 'package:taxi_app/screens/tourist/tourist_home_screen.dart';

class _Reader implements WorkflowNotificationReader {
  String? uid = 'owner';
  int epoch = 1;
  Map<String, dynamic> claims = {};
  final docs = <String, Map<String, dynamic>>{};
  final reads = <String>[];
  Future<void> Function(String)? beforeRead;
  int claimReads = 0;
  @override
  bool current(TripChatPushIntent intent) => intent.belongsTo(uid, epoch);
  @override
  Future<Map<String, dynamic>> refreshedClaims() async {
    claimReads++;
    return Map.of(claims);
  }
  @override
  Future<Map<String, dynamic>?> read(String path) async {
    reads.add(path);
    await beforeRead?.call(path);
    return docs[path];
  }
}
class _Tokens implements FcmTokenPort {
  @override
  Future<String?> prepareToken(String uid) async => null;
  @override
  Future<void> save(String uid, String token) async {}
  @override
  Future<void> detach(String uid) async {}
}
TripChatPushIntent _intent(String type, {String actor = 'owner'}) => TripChatPushIntent.parse(actor,
  {'type': type, if (type.startsWith('support_')) 'supportRequestId': 'r'
    else if (type == 'founding_offer_closed') 'eventId': 'founding_offer_closed'
    else 'accountUid': 'owner', if (type.startsWith('payment_')) 'paymentId': 'p'}, sessionEpoch: 1)!;

_Reader _account({bool driver = false, String registration = 'approved'}) {
  final reader = _Reader();
  reader.docs['users/owner'] = {'accountType': driver ? 'driver' : 'tourist', 'status': 'active',
    'registrationStatus': registration, 'accountStatus': registration == 'approved' ? 'active' : 'pending_approval',
    'applicationRevision': 1, 'identityVerificationStatus': 'verified', 'paymentStatus': 'pending',
    'membershipStatus': 'pending', 'currentRegistrationPaymentId': 'p'};
  reader.docs['registration_applications/owner'] = {'uid': 'owner', 'applicationRevision': 1, 'registrationStatus': registration};
  reader.docs['driver_verifications/owner'] = {'identityVerificationStatus': 'verified'};
  reader.docs['users/owner/payments/p'] = {'paymentType': 'registration', 'status': 'pending', 'claimSubmitted': true};
  return reader;
}

_Reader _upgrade(String state) {
  final reader = _account(driver: state == 'approved');
  reader.docs['users/owner']!['driverUpgradeStatus'] = state;
  reader.docs['registration_applications/owner']!.addAll({'purpose': 'driver_upgrade',
    'accountType': 'tourist', 'targetAccountType': 'driver', 'registrationStatus': state});
  return reader;
}

void main() {
  for (final type in TripChatPushIntent.workflowBodies.keys) {
    test('$type parses only identifiers and preserves session epoch', () {
      final intent = _intent(type);
      expect(intent.isWorkflow, isTrue);
      expect(intent.type, type);
      expect(intent.belongsTo('owner', 1), isTrue);
      expect(intent.belongsTo('other', 1), isFalse);
      expect(intent.belongsTo('owner', 3), isFalse);
      expect(TripChatPushIntent.parse('owner', intent.routingData)?.routingData, intent.routingData);
      expect(TripChatPushIntent.parse(null, intent.routingData), isNull);
      final key = type.startsWith('support_') ? 'supportRequestId' : type == 'founding_offer_closed' ? 'eventId' : 'accountUid';
      expect(TripChatPushIntent.parse('owner', {...intent.routingData, key: '../private'}), isNull);
    });
  }
  test('payment type requires a payment document ID, never a payment reference', () {
    expect(TripChatPushIntent.parse('owner', {'type': 'payment_verified', 'accountUid': 'owner'}), isNull);
    expect(TripChatPushIntent.parse('owner', {'type': 'payment_verified', 'accountUid': 'owner', 'paymentId': 'x/y'}), isNull);
  });
  test('support reply owner access works for pending users without operational access', () async {
    final reader = _Reader()..docs['support_requests/r'] = {'id': 'r', 'userId': 'owner'};
    final intent = _intent('support_admin_reply');
    final target = await WorkflowNotificationResolver(reader).resolve(intent);
    expect(target, WorkflowDestination.supportOwner);
    expect(workflowNotificationDestination(intent, target), isA<SupportThreadScreen>());
    reader.docs['support_requests/r']!['userId'] = 'someone-else';
    await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
  });
  test('support staff authorization uses supportAdmin, not accountType or primary-only claim', () async {
    final reader = _Reader()..uid = 'admin';
    reader.docs['support_requests/r'] = {'id': 'r', 'userId': 'owner'};
    final intent = _intent('support_new_request', actor: 'admin');
    for (final claims in <Map<String, dynamic>>[{}, {'admin': true}, {'accountType': 'admin'}]) {
      reader.claims = claims;
      await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
    }
    reader.claims = {'supportAdmin': true};
    final target = await WorkflowNotificationResolver(reader).resolve(intent);
    expect(target, WorkflowDestination.supportAdmin);
    expect(workflowNotificationDestination(intent, target), isA<AdminSupportDetailScreen>());
    expect(await WorkflowNotificationResolver(reader).resolve(_intent('support_user_reply', actor: 'admin')), target);
  });
  test('registration reviewer must be primary admin and revision still pending', () async {
    final reader = _account(registration: 'pending_review')..uid = 'admin';
    final intent = _intent('registration_submitted', actor: 'admin');
    reader.claims = {'supportAdmin': true};
    await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
    reader.claims = {'admin': true};
    final target = await WorkflowNotificationResolver(reader).resolve(intent);
    expect(target, WorkflowDestination.adminApplication);
    expect(workflowNotificationDestination(intent, target), isA<AdminUserDetailScreen>());
    reader.docs['users/owner']!['registrationStatus'] = 'approved';
    await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
  });
  for (final state in ['correction_required', 'rejected']) {
    test('$state routes owner to current application, unrelated account denied', () async {
      final reader = _account(registration: state);
      final intent = _intent('registration_$state');
      final target = await WorkflowNotificationResolver(reader).resolve(intent);
      expect(target, WorkflowDestination.application);
      expect(workflowNotificationDestination(intent, target), isA<RegistrationApplicationScreen>());
      reader.uid = 'other';
      await expectLater(WorkflowNotificationResolver(reader).resolve(_intent(intent.type, actor: 'other')), throwsStateError);
    });
  }
  test('approved Tourist goes home; driver approval alone cannot grant dashboard access', () async {
    final tourist = _account();
    final touristIntent = _intent('registration_approved');
    final target = await WorkflowNotificationResolver(tourist).resolve(touristIntent);
    expect(target, WorkflowDestination.touristHome);
    expect(workflowNotificationDestination(touristIntent, target), isA<TouristHomeScreen>());
    final driver = _account(driver: true);
    final driverIntent = _intent('registration_driver_approved');
    final next = await WorkflowNotificationResolver(driver).resolve(driverIntent);
    expect(next, WorkflowDestination.driverStatus);
    expect(workflowNotificationDestination(driverIntent, next), isA<DriverRegistrationStatusScreen>());
    expect(driverIntent.body, contains('remaining account steps'));
  });
  test('identity notices reload private verification while users remains authoritative', () async {
    final reader = _account(driver: true);
    for (final type in ['identity_verified', 'identity_action_required']) {
      expect(await WorkflowNotificationResolver(reader).resolve(_intent(type)), WorkflowDestination.driverStatus);
    }
    expect(reader.reads, contains('driver_verifications/owner'));
    reader.docs['driver_verifications/owner']!['membershipStatus'] = 'active';
    expect(await WorkflowNotificationResolver(reader).resolve(_intent('identity_verified')), WorkflowDestination.driverStatus);
  });
  test('payment proof routes primary admin to payment review; owner decisions go to current next step', () async {
    final reader = _account(driver: true)..uid = 'admin';
    final intent = _intent('payment_submitted', actor: 'admin');
    reader.claims = {'supportAdmin': true};
    await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
    reader.claims = {'admin': true};
    final target = await WorkflowNotificationResolver(reader).resolve(intent);
    expect(target, WorkflowDestination.adminPayment);
    final page = workflowNotificationDestination(intent, target) as AdminUserDetailScreen;
    expect(page.paymentFocus, isTrue);
    reader.uid = 'owner'; reader.claims = {};
    for (final type in ['payment_verified', 'payment_rejected']) {
      expect(await WorkflowNotificationResolver(reader).resolve(_intent(type)), WorkflowDestination.driverStatus);
    }
    reader.docs['users/owner']!['currentRegistrationPaymentId'] = 'replacement';
    await expectLater(WorkflowNotificationResolver(reader).resolve(_intent('payment_verified')), throwsStateError);
  });
  test('membership notification reaches dashboard only when current operational requirements pass', () async {
    final reader = _account(driver: true);
    final intent = _intent('membership_activated');
    expect(await WorkflowNotificationResolver(reader).resolve(intent), WorkflowDestination.driverStatus);
    reader.docs['users/owner']!.addAll({'paymentStatus': 'verified', 'membershipStatus': 'active', 'membershipPlan': 'founding_lifetime'});
    final target = await WorkflowNotificationResolver(reader).resolve(intent);
    expect(target, WorkflowDestination.driverHome);
    expect(workflowNotificationDestination(intent, target), isA<DriverHomeScreen>());
    reader.docs['users/owner']!['accountStatus'] = 'suspended';
    expect(await WorkflowNotificationResolver(reader).resolve(intent), WorkflowDestination.driverStatus);
  });
  test('annual expiry is evaluated by existing driver eligibility helper', () async {
    final reader = _account(driver: true);
    reader.docs['users/owner']!.addAll({'paymentStatus': 'verified', 'membershipStatus': 'active',
      'membershipPlan': 'standard_annual', 'membershipValidUntil': DateTime.now().add(const Duration(days: 1))});
    final intent = _intent('membership_activated');
    expect(await WorkflowNotificationResolver(reader).resolve(intent), WorkflowDestination.driverHome);
    reader.docs['users/owner']!['membershipValidUntil'] = DateTime.utc(2000);
    expect(await WorkflowNotificationResolver(reader).resolve(intent), WorkflowDestination.driverStatus);
  });
  test('founding event requires current primary claim and actual event', () async {
    final reader = _Reader()..uid = 'admin';
    final intent = _intent('founding_offer_closed', actor: 'admin');
    reader.docs['admin_notifications/founding_offer_closed'] = {'type': 'founding_offer_closed', 'registrationNumber': 100};
    await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
    reader.claims = {'admin': true};
    final target = await WorkflowNotificationResolver(reader).resolve(intent);
    expect(workflowNotificationDestination(intent, target), isA<AdminDashboardScreen>());
  });
  test('logout/account switch during read rejects result; revocation also rejects', () async {
    final reader = _Reader()..uid = 'admin'..claims = {'supportAdmin': true};
    reader.docs['support_requests/r'] = {'id': 'r', 'userId': 'owner'};
    final entered = Completer<void>(), release = Completer<void>();
    reader.beforeRead = (_) async { entered.complete(); await release.future; };
    final result = WorkflowNotificationResolver(reader).resolve(_intent('support_user_reply', actor: 'admin'));
    final rejected = expectLater(result, throwsStateError);
    await entered.future;
    reader.epoch = 3; // Even switch-away-and-back to admin cannot reuse this load.
    release.complete(); await rejected;
    reader.epoch = 1;
    reader.beforeRead = (_) async { reader.claims = {}; };
    await expectLater(WorkflowNotificationResolver(reader).resolve(_intent('support_new_request', actor: 'admin')), throwsStateError);
  });
  test('logout clears pending workflow intent through shared session mechanism', () async {
    TripChatPushIntent? pending;
    final session = FcmSession(_Tokens(), onUserChanged: (_) => pending = null);
    await session.changeUser('owner');
    pending = _intent('registration_rejected');
    final logout = session.beforeLogout('owner');
    expect(pending, isNull);
    await logout;
  });
  test('session change after profile read stops all subsequent private reads', () async {
    final reader = _account(driver: true);
    reader.beforeRead = (path) async {
      if (path == 'users/owner') {
        reader.uid = 'other';
        reader.epoch++;
      }
    };
    await expectLater(WorkflowNotificationResolver(reader).resolve(_intent('payment_verified')), throwsStateError);
    expect(reader.reads, ['users/owner']);
  });
  test('missing/server-denied records fail safely without destination', () async {
    final reader = _Reader();
    await expectLater(WorkflowNotificationResolver(reader).resolve(_intent('support_admin_reply')), throwsStateError);
    reader.beforeRead = (_) async => throw StateError('permission-denied');
    await expectLater(WorkflowNotificationResolver(reader).resolve(_intent('support_admin_reply')), throwsStateError);
  });
  for (final state in ['correction_required', 'rejected']) {
    test('upgrade $state opens current owner upgrade instead of active Tourist home', () async {
      final reader = _upgrade(state);
      final intent = _intent('driver_upgrade_$state');
      final target = await WorkflowNotificationResolver(reader).resolve(intent);
      expect(target, WorkflowDestination.application);
      final screen = workflowNotificationDestination(intent, target) as RegistrationApplicationScreen;
      expect(screen.uid, 'owner'); expect(screen.upgradeRequest, isTrue);
      reader.uid = 'other';
      await expectLater(WorkflowNotificationResolver(reader).resolve(_intent(intent.type, actor: 'other')), throwsStateError);
    });
  }
  test('upgrade reviewer needs current primary claim; revoked and support-only users denied', () async {
    final reader = _upgrade('pending_review')..uid = 'admin';
    final intent = _intent('driver_upgrade_submitted', actor: 'admin');
    for (final claims in <Map<String, dynamic>>[{}, {'supportAdmin': true}]) {
      reader.claims = claims;
      await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
    }
    reader.claims = {'admin': true};
    final target = await WorkflowNotificationResolver(reader).resolve(intent);
    expect(target, WorkflowDestination.adminApplication);
    expect(workflowNotificationDestination(intent, target), isA<AdminUserDetailScreen>());
    reader.beforeRead = (path) async {
      if (path.startsWith('registration_applications/')) { reader.claims = {}; }
    };
    await expectLater(WorkflowNotificationResolver(reader).resolve(intent), throwsStateError);
  });
  test('upgrade tap rejects wrong purpose, owner, revision and session switch', () async {
    for (final patch in [{'purpose': 'registration'}, {'uid': 'other'}, {'applicationRevision': 2}, {'registrationStatus': 'draft'}]) {
      final reader = _upgrade('rejected'); reader.docs['registration_applications/owner']!.addAll(patch);
      await expectLater(WorkflowNotificationResolver(reader).resolve(_intent('driver_upgrade_rejected')), throwsStateError);
    }
    final reader = _upgrade('rejected');
    reader.beforeRead = (_) async { reader.epoch++; };
    await expectLater(WorkflowNotificationResolver(reader).resolve(_intent('driver_upgrade_rejected')), throwsStateError);
  });
  test('upgrade approval routes to payment status until existing operational gates pass', () async {
    final reader = _upgrade('approved');
    final intent = _intent('driver_upgrade_approved');
    expect(intent.body, contains('remaining payment and membership steps'));
    expect(await WorkflowNotificationResolver(reader).resolve(intent), WorkflowDestination.driverStatus);
    reader.docs['users/owner']!.addAll({'paymentStatus': 'verified', 'membershipStatus': 'active', 'membershipPlan': 'founding_lifetime'});
    expect(await WorkflowNotificationResolver(reader).resolve(intent), WorkflowDestination.driverHome);
    reader.docs['users/owner']!['accountStatus'] = 'suspended';
    expect(await WorkflowNotificationResolver(reader).resolve(intent), WorkflowDestination.driverStatus);
  });
  test('upgrade payment and membership taps reuse existing destinations', () async {
    final reader = _upgrade('approved');
    for (final type in ['payment_verified', 'payment_rejected', 'membership_activated']) {
      expect(await WorkflowNotificationResolver(reader).resolve(_intent(type)), WorkflowDestination.driverStatus);
    }
    reader.uid = 'admin'; reader.claims = {'admin': true};
    expect(await WorkflowNotificationResolver(reader).resolve(_intent('payment_submitted', actor: 'admin')), WorkflowDestination.adminPayment);
  });
  test('logout clears upgrade pending intent through the existing session', () async {
    TripChatPushIntent? pending;
    final session = FcmSession(_Tokens(), onUserChanged: (_) => pending = null);
    await session.changeUser('owner'); pending = _intent('driver_upgrade_approved');
    final logout = session.beforeLogout('owner'); expect(pending, isNull); await logout;
  });
}
