import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/account_attention.dart';
import 'package:taxi_app/core/models/admin_user_summary.dart';
import 'package:taxi_app/core/models/registration_application.dart';
import 'package:taxi_app/core/models/driver_administration.dart';
import 'package:taxi_app/core/services/admin_service.dart';
import 'package:taxi_app/core/services/admin_registration_queue_service.dart';
import 'package:taxi_app/screens/admin/admin_registration_queue_screen.dart';
import 'package:taxi_app/screens/auth/session_navigation.dart';
import 'package:taxi_app/screens/auth/registration_application_screen.dart';
import 'package:taxi_app/screens/driver/driver_home_screen.dart';

void main() {
  test('Upgrade summary keeps purpose, current state and latest upgrade time without private fields', () {
    final stamp = Timestamp.fromDate(DateTime.utc(2026, 10, 2));
    for (final approved in [false, true]) {
      final row = RegistrationQueueRow.fromMap('upgrade', {'fullName': 'Upgrade Applicant',
        'accountType': approved ? 'driver' : 'tourist', 'registrationStatus': 'approved',
        'driverUpgradeStatus': approved ? 'approved' : 'pending_review', 'applicationRevision': 3,
        'driverUpgradeSubmittedAt': stamp, 'applicationSubmittedAt': Timestamp.fromMillisecondsSinceEpoch(1),
        'nicNumber': 'PRIVATE-NIC', 'drivingLicenceNumber': 'PRIVATE-DL', 'nicRegistryKey': 'PRIVATE-HMAC',
      }, purpose: 'driver_upgrade');
      expect(row.purposeLabel, 'Driver Upgrade'); expect(row.revision, 3);
      expect(row.applicationState, approved ? 'approved' : 'pending_review');
      expect(row.submittedAt, stamp.toDate().toUtc());
      for (final secret in ['PRIVATE-NIC', 'PRIVATE-DL', 'PRIVATE-HMAC']) {
        expect(row.user.matchesSearch(secret), isFalse);
      }
    }
    expect(RegistrationQueueRow.fromMap('new-tourist', {'accountType': 'tourist'}, purpose: 'registration').purposeLabel, 'New Tourist registration');
    expect(RegistrationQueueRow.fromMap('new-driver', {'accountType': 'driver'}, purpose: 'registration').purposeLabel, 'New Driver / Partner registration');
  });
  testWidgets('Upgrade filter, correction and payment handoff preserve the same identifiable applicant', (tester) async {
    final queue = _QueueService()..upgrade = true;
    await tester.pumpWidget(MaterialApp(home: AdminRegistrationQueueScreen(service: queue)));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade Applicant'), findsOneWidget);
    expect(find.textContaining('Driver Upgrade\nApplication: pending review'), findsOneWidget);
    await tester.tap(find.text('Driver Upgrades')); await tester.pumpAndSettle();
    expect(queue.last, RegistrationQueueFilter.upgrade); expect(find.text('Upgrade Applicant'), findsOneWidget);
    queue.corrected = true;
    await tester.tap(find.text('Correction Required')); await tester.pumpAndSettle();
    expect(find.textContaining('Application: correction required'), findsOneWidget);
    queue.approved = true;
    await tester.tap(find.text('All')); await tester.pumpAndSettle();
    expect(find.text('Upgrade Applicant'), findsNothing);
    await tester.tap(find.text('Payment & Activation')); await tester.pumpAndSettle();
    expect(find.text('Upgrade Applicant'), findsOneWidget);
    expect(find.textContaining('Driver Upgrade'), findsWidgets);
    expect(find.textContaining('AWAITING PAYMENT / MEMBERSHIP'), findsOneWidget);
    await tester.tap(find.text('Driver Upgrades')); await tester.pumpAndSettle();
    expect(find.text('Upgrade Applicant'), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
  });
  test('Signed-in driver stays in status flow through payment and activation', () {
    final profile = <String, dynamic>{'status': 'active', 'accountType': 'driver', 'registrationStatus': 'approved',
      'identityVerificationStatus': 'verified', 'accountStatus': 'pending_approval', 'paymentStatus': 'pending',
      'membershipStatus': 'pending', 'membershipPlan': 'founding_lifetime'};
    expect(sessionDestination('driver', profile), isA<RegistrationApplicationScreen>());
    expect(driverActivationMessage(profile), contains('Complete the registration payment'));
    profile['paymentStatus'] = 'verified';
    expect(sessionDestination('driver', profile), isA<RegistrationApplicationScreen>());
    expect(driverActivationMessage(profile), contains('Waiting for membership activation'));
    profile.addAll({'membershipStatus': 'active', 'accountStatus': 'active'});
    expect(sessionDestination('driver', profile), isA<DriverHomeScreen>());
  });

  test('Queue reads the current server submission timestamp, not creation/update dates', () {
    final first = Timestamp.fromDate(DateTime.utc(2026, 9, 23, 10));
    final latest = Timestamp.fromDate(DateTime.utc(2026, 9, 24, 11));
    final profile = <String, dynamic>{'applicationRevision': 1, 'applicationSubmittedAt': first,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1), 'updatedAt': Timestamp.fromMillisecondsSinceEpoch(2)};
    final original = RegistrationQueueRow.fromMap('applicant', profile);
    expect(original.submittedAt, first.toDate().toUtc());
    profile.addAll({'applicationRevision': 2, 'applicationSubmittedAt': latest});
    final resubmitted = RegistrationQueueRow.fromMap('applicant', profile);
    expect(resubmitted.submittedAt, latest.toDate().toUtc());
    expect(resubmitted.revision, 2);
    expect(original.submittedAt, first.toDate().toUtc());
    for (final value in [null, 'invalid', 123]) {
      expect(RegistrationQueueRow.fromMap('legacy', {'applicationSubmittedAt': value}).submittedAt, isNull);
    }
    expect(RegistrationQueueRow.fromMap('legacy', {}).submittedAt, isNull);
  });
  test('Legacy active never overrides pending registration labels', () {
    for (final entry in {'draft': 'DRAFT', 'pending_review': 'PENDING APPROVAL',
      'correction_required': 'CORRECTION REQUIRED', 'rejected': 'REJECTED'}.entries) {
      final user = {'status': 'active', 'registrationStatus': entry.key, 'accountType': 'tourist', 'accountStatus': 'active'};
      expect(accountStatusLabel(user), entry.value);
      expect(applicationOperational(user), isFalse);
      expect(AdminUserSummary.fromMap('user', user).statusLabel, entry.value);
    }
    expect(accountStatusLabel({'registrationStatus': 'approved', 'accountType': 'tourist', 'accountStatus': 'active'}), 'ACTIVE');
  });
  test('Driver needs current users state, not approved verification/application snapshots', () {
    final user = <String, dynamic>{'status': 'active', 'accountType': 'driver', 'registrationStatus': 'approved',
      'identityVerificationStatus': 'verified', 'paymentStatus': 'pending', 'membershipStatus': 'pending', 'accountStatus': 'pending_approval'};
    final record = DriverAdministration(profile: user, identity: DriverRecord('identity', {
      'identityVerificationStatus': 'verified', 'paymentStatus': 'verified', 'membershipStatus': 'active', 'accountStatus': 'active'}));
    expect(record.paymentStatus, 'pending'); expect(record.membershipStatus, 'pending');
    expect(accountStatusLabel(user), 'AWAITING PAYMENT / MEMBERSHIP');
    expect(sessionDestination('driver', user), isA<RegistrationApplicationScreen>());
    user.addAll({'paymentStatus': 'verified', 'membershipStatus': 'active', 'accountStatus': 'active', 'membershipPlan': 'founding_lifetime'});
    expect(applicationOperational(user), isTrue); expect(accountStatusLabel(user), 'ACTIVE');
    expect(sessionDestination('driver', user), isA<DriverHomeScreen>());
  });
  test('Queue service denies non-primary-admin access before reading accounts', () async {
    final service = AdminRegistrationQueueService(admin: _Admin(allowed: false));
    await expectLater(service.counts(), throwsStateError);
    await expectLater(service.page(RegistrationQueueFilter.all), throwsStateError);
  });
  for (final width in [360.0, 1400.0]) {
    testWidgets('Pending queue is safe and refreshes attention rows at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final queue = _QueueService();
      await tester.pumpWidget(MaterialApp(home: AdminRegistrationQueueScreen(service: queue)));
      await tester.pumpAndSettle();
      expect(find.text('Applicant'), findsOneWidget);
      expect(find.textContaining('901234567V'), findsNothing);
      expect(find.textContaining('B1234567'), findsNothing);
      expect(find.textContaining('PENDING APPROVAL'), findsOneWidget);
      expect(find.textContaining('Submitted: ${DateTime.utc(2026, 9, 23).toLocal()}'), findsOneWidget);
      // Authoritative account has been approved; refresh must remove the prior row.
      queue.approved = true;
      await tester.tap(find.text('Refresh registrations')); await tester.pumpAndSettle();
      expect(find.text('Applicant'), findsNothing);
      await tester.tap(find.text('Payment & Activation')); await tester.pumpAndSettle();
      expect(queue.last, RegistrationQueueFilter.payment);
      expect(find.text('Approved Driver'), findsOneWidget);
      expect(find.textContaining('AWAITING PAYMENT / MEMBERSHIP'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Dashboard entries show identity and pending-payment counts', (tester) async {
    final queue = _QueueService();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PendingRegistrationsEntry(admin: queue.admin, service: queue))));
    await tester.pumpAndSettle();
    expect(find.text('Pending Registrations'), findsOneWidget); expect(find.text('Payment & Activation'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('1 awaiting membership activation'), findsOneWidget);
  });
}
class _Admin extends AdminService {
  _Admin({this.allowed = true});
  final bool allowed;
  @override
  Future<AdminAccess> readAccess({bool forceRefresh = false}) async => AdminAccess(allowed ? AdminAccessStatus.allowed : AdminAccessStatus.denied, uid: 'admin');
  @override
  Stream<AdminAccess> watchAccess() => Stream.fromFuture(readAccess());
}
class _QueueService extends AdminRegistrationQueueService {
  _QueueService() : super(admin: _Admin());
  bool approved = false;
  bool upgrade = false, corrected = false;
  RegistrationQueueFilter? last;
  @override
  Future<RegistrationQueueCounts> counts() async => const RegistrationQueueCounts(3, 2, 1);
  @override
  Future<RegistrationQueuePage> page(RegistrationQueueFilter filter, {String? afterUid}) async {
    last = filter;
    final payment = filter == RegistrationQueueFilter.payment;
    if (upgrade) {
      if ((approved && !payment && filter != RegistrationQueueFilter.upgrade) ||
          (!approved && payment) || (filter == RegistrationQueueFilter.correction && !corrected)) {
        return RegistrationQueuePage([], null);
      }
      return RegistrationQueuePage([RegistrationQueueRow.fromMap('upgrade', {
        'fullName': 'Upgrade Applicant', 'accountType': approved ? 'driver' : 'tourist',
        'registrationStatus': 'approved', 'driverUpgradeStatus': approved ? 'approved' : corrected ? 'correction_required' : 'pending_review',
        'accountStatus': approved ? 'pending_approval' : 'active', 'applicationRevision': 3,
        'driverUpgradeSubmittedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 2)),
        'nicNumber': 'PRIVATE-NIC', 'drivingLicenceNumber': 'PRIVATE-DL',
      }, purpose: 'driver_upgrade')], null);
    }
    if (approved && !payment) { return RegistrationQueuePage([], null); }
    return RegistrationQueuePage([RegistrationQueueRow.fromMap('applicant', {
      'fullName': payment ? 'Approved Driver' : 'Applicant', 'accountType': payment ? 'driver' : 'tourist',
      'status': 'active', 'registrationStatus': payment ? 'approved' : 'pending_review', 'accountStatus': 'pending_approval',
      'phoneNumber': '0771234567', 'nicNumber': '901234567V', 'drivingLicenceNumber': 'B1234567',
      'applicationRevision': 1, 'applicationSubmittedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 23)),
    })], null);
  }
}
