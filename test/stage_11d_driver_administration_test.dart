import 'dart:async';
import 'package:taxi_app/core/validation/driver_action_validation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/admin_dashboard_stats.dart';
import 'package:taxi_app/core/models/admin_user_summary.dart';
import 'package:taxi_app/core/models/driver_administration.dart';
import 'package:taxi_app/core/services/admin_service.dart';
import 'package:taxi_app/core/services/driver_administration_service.dart';
import 'package:taxi_app/core/widgets/driver_administration_panel.dart';
import 'package:taxi_app/screens/admin/admin_user_detail_screen.dart';
import 'package:taxi_app/screens/admin/admin_users_screen.dart';
import 'package:taxi_app/screens/admin/admin_dashboard_screen.dart';
import 'package:taxi_app/screens/driver/driver_registration_status_screen.dart';

DriverAdministration data({String identity = 'pending', String payment = 'pending', String type = 'driver',
  Map<String, dynamic> extra = const {}}) => DriverAdministration(profile: {
    'accountType': type, 'fullName': 'Test Driver', 'status': 'active', 'accountStatus': 'active',
    'identityVerificationStatus': identity, 'paymentStatus': payment, 'membershipStatus': 'pending',
    'driverAdminRevision': 4, ...extra,
  }, identity: DriverRecord('driver', {'identityVerificationStatus': identity, 'nicNumber': '901234567V',
    'drivingLicenceNumber': 'B1234567', 'nicDocumentPath': 'private/nic', 'drivingLicenceDocumentPath': 'private/licence',
    'selfiePath': 'private/selfie'}), payments: [DriverRecord('payment', {
      'paymentReference': 'CT-PAY-260919-A8K4Q2', 'status': payment, 'paymentType': 'registration',
      'quotedRegistrationFeeLkr': 3500, 'quotedMembershipPlan': 'founding_lifetime',
      'quotedAnnualRenewalRequired': false, 'quotedAnnualRenewalFeeLkr': null,
      'quotedAt': Timestamp.fromDate(DateTime.utc(2026, 9, 19)), 'foundingOfferOpenAtQuote': true,
      'expectedAmountLkr': 3500, 'claimedAmountLkr': 3500, 'claimedPaymentDate': '2026-09-19',
      'claimSubmitted': true, 'bankTransactionReference': 'BANK-123', 'depositorName': 'Depositor', 'slipPath': 'private/slip',
    })]);
Future<void> pump(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) { await tester.pump(); }
}
Future<void> reveal(WidgetTester tester, Finder finder) async {
  // The fixture mounts the entire panel Column as one ListView child, so its
  // targets already exist even when outside the viewport. Fail on stale labels
  // instead of dragging repeatedly and eventually throwing from an empty finder.
  expect(finder, findsOneWidget, reason: 'Expected one panel target before revealing it.');
  final target = tester.element(finder);
  if (Scrollable.maybeOf(target) != null) {
    await tester.ensureVisible(finder);
  }
  await pump(tester);
}
Future<void> tapIdentitySubmit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('submit_identity'));
  expect(submit, findsOneWidget);
  // Text entry leaves the licence field focused. Finish its focus/keyboard
  // transition before scrolling, so caret visibility cannot undo our reveal.
  FocusScope.of(tester.element(submit)).unfocus();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await reveal(tester, submit);
  await tester.ensureVisible(submit);
  await tester.pump();
  // Keep the whole button away from viewport edges, not just barely visible.
  await Scrollable.ensureVisible(tester.element(submit), alignment: .5);
  await tester.pump();
  expect(submit.hitTestable(), findsOneWidget,
    reason: 'Identity submit must receive a real tap after editing the fields.');
  await tester.tap(submit);
  await pump(tester);
}

Future<void> _panel(WidgetTester tester, _DriverService service, {bool admin = true}) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: ListView(children: [
    DriverAdministrationPanel(uid: 'driver', admin: admin, service: service)]))));
  await pump(tester);
}

void main() {
  test('Payment preflight rejects invalid amount and calendar date with specific errors', () {
    for (final value in ['0', '-1', 'abc', '3500.50']) {
      expect(validateDriverActionField('claimedAmountLkr', value, 'Amount'), contains('positive payment amount'));
    }
    expect(validateDriverActionField('claimedPaymentDate', '2026-02-31', 'Date'), contains('valid payment date'));
    expect(validateDriverActionField('claimedPaymentDate', '2026-09-24', 'Date'), isNull);
    expect(validateDriverActionField('depositorName', '  ', 'Depositor'), 'Depositor name is required.');
  });

  testWidgets('Payment Confirm identifies every missing field, including depositor', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DriverActionDialog(
      title: 'Submit payment claim', admin: false, explanation: 'Review your payment.',
      fields: const {'claimedAmountLkr': 'Claimed amount', 'claimedPaymentDate': 'Payment date',
        'bankTransactionReference': 'Bank transaction reference', 'depositorName': 'Depositor name'}))));
    await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pump();
    for (final message in ['Enter the payment amount.', 'Select the payment date.',
      'Bank transaction reference is required.', 'Depositor name is required.']) {
      expect(find.text(message), findsWidgets);
    }
    for (final entry in {'claimedAmountLkr': '3500', 'claimedPaymentDate': '2026-09-24', 'bankTransactionReference': 'BANK-123'}.entries) {
      await tester.enterText(find.byKey(ValueKey('driver_input_${entry.key}')), entry.value);
    }
    await tester.ensureVisible(find.byKey(const Key('confirm_driver_action')));
    await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pump();
    expect(find.text('Depositor name is required.'), findsNWidgets(2));
    expect(find.byType(DriverActionDialog), findsOneWidget);
  });
  testWidgets('Approved application does not offer duplicate identity review; account controls are explicit', (tester) async {
    await _panel(tester, _DriverService(data(identity: 'verified', extra: {'registrationStatus': 'approved'})));
    expect(find.text('Registration: APPROVED'), findsOneWidget);
    expect(find.text('Identity verification: VERIFIED'), findsOneWidget);
    expect(find.byKey(const ValueKey('verify_identity')), findsNothing);
    await reveal(tester, find.text('Set account suspended'));
    expect(find.text('Account status controls'), findsOneWidget);
  });

  test('Missing legacy fields are safe and do not confer bidding eligibility', () {
    for (final fields in <Map<String, dynamic>>[{}, {'driverAdminRevision': 'bad', 'identityVerificationStatus': null,
      'paymentStatus': [], 'membershipStatus': false, 'membershipValidUntil': 'invalid'}]) {
      final value = DriverAdministration(profile: fields);
      expect(value.revision, 0); expect(value.identityStatus, 'pending');
      expect(value.paymentStatus, 'pending'); expect(value.membershipStatus, 'pending');
      expect(value.canActivate, isFalse); expect(driverCanBid(fields), isFalse);
    }
    expect(DriverAdministration.display({'unexpected': true}), 'Not available');
    expect(DriverAdministration.date('invalid'), isNull);
  });

  test('Bidding requires all five states and a current annual term; lifetime has no expiry', () {
    final ready = {'accountType': 'driver', 'identityVerificationStatus': 'verified', 'paymentStatus': 'verified',
      'membershipStatus': 'active', 'accountStatus': 'active', 'membershipPlan': 'founding_lifetime'};
    expect(driverCanBid(ready), isTrue);
    for (final key in ['accountType', 'identityVerificationStatus', 'paymentStatus', 'membershipStatus', 'accountStatus']) {
      expect(driverCanBid({...ready, key: 'pending'}), isFalse, reason: key);
    }
    final now = DateTime.utc(2026, 9, 19);
    expect(driverCanBid({...ready, 'membershipPlan': 'standard_annual',
      'membershipValidUntil': Timestamp.fromDate(DateTime.utc(2027, 9, 19))}, now: now), isTrue);
    expect(driverCanBid({...ready, 'membershipPlan': 'standard_annual',
      'membershipValidUntil': Timestamp.fromDate(now)}, now: now), isFalse);
    expect(driverCanBid({...ready, 'paymentStatus': 'not_required'}), isFalse);
  });

  test('Denied primary admin cannot read or enqueue any operation', () async {
    final source = _Source(), admin = _Admin()..allowed = false;
    final service = DriverAdministrationService(adminService: admin, dataSource: source);
    await expectLater(service.load('driver', admin: true), throwsStateError);
    await expectLater(service.perform('driver', 'verify_identity', {}, admin: true,
      revision: 0, operationId: 'op'), throwsStateError);
    expect(source.loads, 0); expect(source.commands, isEmpty);
  });

  test('Admin client queues an immutable request rather than writing membership fields', () async {
    final source = _Source();
    final service = DriverAdministrationService(adminService: _Admin(), dataSource: source);
    await service.perform('driver', 'activate_membership', {}, admin: true, revision: 4, operationId: 'op', reason: 'Reviewed');
    expect(source.commands.single.keys.toSet(), {'actorUid', 'action', 'payload', 'expectedRevision', 'reason'});
    expect(source.commands.single['actorUid'], 'admin');
    expect(source.commands.single['payload'], isEmpty);
    expect(source.commands.single['expectedRevision'], 4);
    for (final action in ['delete_user', 'grant_admin', 'change_email', 'submit_identity']) {
      await expectLater(service.perform('driver', action, {}, admin: true, revision: 4, operationId: action), throwsArgumentError);
    }
    expect(source.commands.length, 1);
  });

  test('A rejected backend decision is never presented as client success', () async {
    final source = _Source()..result = DriverRecord('op', {'status': 'failed', 'errorMessage': 'Identity is required.'});
    final service = DriverAdministrationService(adminService: _Admin(), dataSource: source);
    await expectLater(service.perform('driver', 'activate_membership', {}, admin: true, revision: 0, operationId: 'op'),
      throwsA(isA<DriverAdministrationException>()));
  });

  test('Owner identity command contains only numbers and retains authenticated actor and revision', () async {
    final source = _Source();
    final service = _OwnerService(dataSource: source);
    await service.perform('driver', 'submit_identity', {'nicNumber': '901234567V', 'drivingLicenceNumber': 'B1234567'},
      admin: false, revision: 7, operationId: 'identity-op');
    expect(source.commands.single['actorUid'], 'driver');
    expect(source.commands.single['expectedRevision'], 7);
    expect(source.commands.single['payload'], {'nicNumber': '901234567V', 'drivingLicenceNumber': 'B1234567'});
    await expectLater(service.perform('driver', 'verify_identity', {}, admin: false, revision: 7, operationId: 'forged'), throwsArgumentError);
    expect(source.commands.length, 1);
  });

  testWidgets('Non-admin direct account details are denied before loading driver controls', (tester) async {
    final admin = _Admin()..allowed = false;
    final service = _DriverService(data());
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'driver', service: admin, driverService: service)));
    await pump(tester);
    expect(find.text('Check access again'), findsOneWidget); expect(service.loads, 0);
    expect(find.byKey(const ValueKey('verify_identity')), findsNothing);
  });

  testWidgets('Tourist account detail has no identity, payment or membership controls', (tester) async {
    final admin = _Admin()..type = 'tourist';
    final service = _DriverService(data(type: 'tourist'));
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'tourist', service: admin, driverService: service)));
    await pump(tester);
    expect(find.byType(DriverAdministrationPanel), findsNothing); expect(service.loads, 0);
    expect(find.text('Activate membership'), findsNothing); expect(find.text('Verify payment'), findsNothing);
  });

  for (final status in ['pending', 'verified', 'rejected']) {
    testWidgets('Identity and payment $status display independently', (tester) async {
      await _panel(tester, _DriverService(data(identity: status, payment: status)));
      expect(find.text('Identity status: $status'), findsOneWidget);
      await reveal(tester, find.text('Expected amount (LKR): 3500'));
      expect(find.text('Expected amount (LKR): 3500'), findsOneWidget);
      expect(find.text('Payment status: $status'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in ['verify_identity', 'reject_identity']) {
    testWidgets('$action requires manual confirmation and records only the intended command', (tester) async {
      final service = _DriverService(data());
      await _panel(tester, service);
      final button = find.byKey(ValueKey(action));
      await reveal(tester, button); await tester.tap(button); await tester.pumpAndSettle();
      expect(service.calls, isEmpty); expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Cancel')); await tester.pumpAndSettle(); expect(service.calls, isEmpty);
      await tester.tap(button); await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('driver_input_reason')), 'Manually reviewed');
      await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pumpAndSettle();
      expect(service.calls.single['action'], action); expect(service.calls.single['reason'], 'Manually reviewed');
      expect(service.calls.single['payload'], isEmpty);
    });
  }

  testWidgets('Payment review collects bank confirmation; rejection does not edit the submitted claim', (tester) async {
    final service = _DriverService(data());
    await _panel(tester, service);
    await reveal(tester, find.byKey(const ValueKey('verify_payment_payment')));
    await tester.tap(find.byKey(const ValueKey('verify_payment_payment'))); await tester.pumpAndSettle();
    expect(service.calls, isEmpty);
    await tester.enterText(find.byKey(const ValueKey('driver_input_bankRecordReference')), 'BANK-RECORD-123');
    await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pumpAndSettle();
    expect(service.calls.single['payload'], {'paymentId': 'payment', 'bankRecordReference': 'BANK-RECORD-123'});
    expect(service.current.payments.single.data['claimedAmountLkr'], 3500);
    await reveal(tester, find.byKey(const ValueKey('reject_payment_payment')));
    await tester.tap(find.byKey(const ValueKey('reject_payment_payment'))); await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pumpAndSettle();
    expect(find.text('Enter a reason for this decision.'), findsWidgets);
    expect(service.calls, hasLength(1));
    await tester.enterText(find.byKey(const ValueKey('driver_input_reason')), 'Bank transfer could not be confirmed.');
    await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pumpAndSettle();
    expect(service.calls.last['action'], 'reject_payment');
    expect(service.calls.last['payload'], {'paymentId': 'payment'});
  });

  testWidgets('Owner cannot submit a payment claim until its image upload succeeds', (tester) async {
    final initial = data(identity: 'verified');
    final service = _DriverService(DriverAdministration(profile: initial.profile, identity: initial.identity,
      payments: [DriverRecord('payment', {...initial.payments.single.data, 'claimSubmitted': false, 'slipPath': null})]));
    await _panel(tester, service, admin: false);
    final button = find.byKey(const ValueKey('submit_payment_payment'));
    await reveal(tester, button);
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
    expect(find.byKey(const ValueKey('choose_payment_slip')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_input_slipPath')), findsNothing);
    expect(service.calls, isEmpty);
  });

  for (final status in ['inactive', 'suspended', 'active']) {
    testWidgets('Account $status requires explicit confirmation', (tester) async {
      final service = _DriverService(data(extra: {'accountStatus': status == 'active' ? 'inactive' : 'active'}));
      await _panel(tester, service);
      await reveal(tester, find.byKey(ValueKey('account_$status')));
      await tester.tap(find.byKey(ValueKey('account_$status'))); await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pumpAndSettle();
      expect(service.calls.single['action'], 'set_account_status');
      expect(service.calls.single['payload'], {'accountStatus': status});
    });
  }

  testWidgets('Activation is hidden before verified payment and requires identity approval and confirmation', (tester) async {
    for (final state in [('pending', 'verified'), ('verified', 'pending'), ('verified', 'verified')]) {
      await tester.pumpWidget(const SizedBox());
      final service = _DriverService(data(identity: state.$1, payment: state.$2));
      await _panel(tester, service);
      final button = find.byKey(const ValueKey('activate_membership'));
      await reveal(tester, find.text('Membership'));
      if (state.$2 != 'verified') {
        expect(button, findsNothing);
        continue;
      }
      await reveal(tester, button);
      final enabled = state.$1 == 'verified' && state.$2 == 'verified';
      expect(tester.widget<OutlinedButton>(button).onPressed != null, enabled);
      if (enabled) {
        await tester.tap(button); await tester.pumpAndSettle(); expect(service.calls, isEmpty);
        await tester.tap(find.byKey(const Key('confirm_driver_action'))); await tester.pumpAndSettle();
        expect(service.calls.single['action'], 'activate_membership'); expect(service.calls.single['payload'], isEmpty);
      }
    }
  });

  for (final width in [360.0, 1400.0]) {
    testWidgets('Driver sections render at $width without prohibited account controls', (tester) async {
      tester.view.physicalSize = Size(width, 1800); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await _panel(tester, _DriverService(data()));
      for (final label in ['Identity', 'Payment & Membership', 'Membership', 'Account status controls', 'Admin history']) {
        await reveal(tester, find.text(label)); expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Account status: active'), findsOneWidget);
      for (final status in ['active', 'inactive', 'suspended']) {
        expect(find.text('Set account $status'), findsOneWidget);
      }
      for (final text in ['Delete account', 'Change email', 'Change phone', 'Reset password', 'Grant admin', 'Edit ratings']) {
        expect(find.text(text, skipOffstage: false), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Driver owner submits numbers inline without uploads or approval controls', (tester) async {
    final service = _DriverService(DriverAdministration(profile: data().profile));
    await tester.pumpWidget(MaterialApp(home: DriverRegistrationStatusScreen(uid: 'driver', service: service)));
    await pump(tester);
    expect(find.text('Identity verification'), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_input_nicNumber')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_input_drivingLicenceNumber')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_input_nicDocumentPath')), findsNothing);
    expect(find.text('Verify identity'), findsNothing); expect(find.text('Reject identity'), findsNothing);
    await tapIdentitySubmit(tester);
    expect(service.calls, isEmpty);
    expect(find.text('Enter your NIC number.'), findsOneWidget);
    expect(find.text('Enter your driving licence number.'), findsOneWidget);
    for (final entry in {'nicNumber': ' 901234567V ', 'drivingLicenceNumber': ' b-1234567 '}.entries) {
      final input = find.byKey(ValueKey('driver_input_${entry.key}'));
      await tester.ensureVisible(input); await tester.enterText(input, entry.value);
    }
    await tapIdentitySubmit(tester);
    expect(service.calls, hasLength(1));
    expect(service.calls.single['action'], 'submit_identity'); expect(service.calls.single['admin'], false);
    expect(service.calls.single['revision'], 4);
    expect(service.calls.single['payload'], {'nicNumber': '901234567V', 'drivingLicenceNumber': 'b-1234567'});
    expect(find.text('Identity submitted for admin review'), findsWidgets);
    expect(find.byKey(const ValueKey('submit_identity')), findsNothing);
  });

  testWidgets('Pending identity is masked and prevents normal duplicate submission', (tester) async {
    final service = _DriverService(data());
    await _panel(tester, service, admin: false);
    expect(find.text('Identity submitted for admin review'), findsOneWidget);
    expect(find.text('NIC: ******567V'), findsOneWidget);
    expect(find.text('Driving licence: ****4567'), findsOneWidget);
    expect(find.textContaining('901234567V'), findsNothing);
    expect(find.textContaining('B1234567'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byKey(const ValueKey('submit_identity')), findsNothing);
    expect(service.calls, isEmpty);
  });

  testWidgets('Unconfirmed identity result pauses another submission until refreshed', (tester) async {
    final service = _DriverService(DriverAdministration(profile: data().profile))
      ..submissionError = StateError('Connection interrupted');
    await _panel(tester, service, admin: false);
    for (final entry in {'nicNumber': '901234567V', 'drivingLicenceNumber': 'B1234567'}.entries) {
      final field = find.byKey(ValueKey('driver_input_${entry.key}'));
      await tester.ensureVisible(field); await tester.enterText(field, entry.value);
    }
    final submit = find.byKey(const ValueKey('submit_identity'));
    await tapIdentitySubmit(tester);
    expect(service.calls.length, 1);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(find.textContaining('Action not confirmed.'), findsOneWidget);
    service.current = data();
    final refresh = find.widgetWithIcon(IconButton, Icons.refresh);
    await tester.ensureVisible(refresh); await tester.pumpAndSettle();
    await tester.tap(refresh); await tester.pumpAndSettle();
    expect(find.text('Identity submitted for admin review'), findsOneWidget);
    expect(submit, findsNothing);
    expect(service.calls.length, 1);
  });

  testWidgets('Rejected identity shows reason and accepts corrected numbers at current revision', (tester) async {
    final rejected = data(identity: 'rejected', extra: {'driverAdminRevision': 9});
    final service = _DriverService(DriverAdministration(profile: rejected.profile,
      identity: DriverRecord('driver', {...rejected.identity!.data, 'rejectionReason': 'Check the licence number'})));
    await _panel(tester, service, admin: false);
    expect(find.text('Rejection reason: Check the licence number'), findsOneWidget);
    for (final entry in {'nicNumber': '199012304567', 'drivingLicenceNumber': 'B7654321'}.entries) {
      final field = find.byKey(ValueKey('driver_input_${entry.key}'));
      await tester.ensureVisible(field); await tester.enterText(field, entry.value);
    }
    expect(find.text('Resubmit identity'), findsOneWidget);
    await tapIdentitySubmit(tester);
    expect(service.calls, hasLength(1));
    expect(service.calls.single['revision'], 9);
    expect(service.calls.single['payload'], {'nicNumber': '199012304567', 'drivingLicenceNumber': 'B7654321'});
    expect(find.text('Identity submitted for admin review'), findsWidgets);
  });

  testWidgets('Tourist owner route does not offer identity inputs', (tester) async {
    await _panel(tester, _DriverService(data(type: 'tourist')), admin: false);
    expect(find.text('Identity verification'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byKey(const ValueKey('submit_identity')), findsNothing);
  });

  testWidgets('Ineligible driver sees clear bidding guidance', (tester) async {
    await _panel(tester, _DriverService(DriverAdministration(profile: data().profile)), admin: false);
    expect(find.text(driverEligibilityMessage), findsOneWidget);
    expect(driverEligibilityMessage, 'Complete driver verification and membership activation before submitting bids.');
  });

  testWidgets('Private admin review displays submitted numbers and enables review actions without uploads', (tester) async {
    await _panel(tester, _DriverService(DriverAdministration(profile: data().profile, identity: DriverRecord('driver', {
      'identityVerificationStatus': 'pending', 'nicNumber': '901234567V', 'drivingLicenceNumber': 'B1234567',
    }))));
    expect(find.text('NIC: 901234567V'), findsOneWidget);
    expect(find.text('Driving licence: B1234567'), findsOneWidget);
    for (final key in ['verify_identity', 'reject_identity']) {
      expect(tester.widget<OutlinedButton>(find.byKey(ValueKey(key))).onPressed, isNotNull);
    }
  });

  testWidgets('Normal admin account list does not expose private NIC or licence values', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: _ListAdmin())));
    await pump(tester);
    expect(find.text('Test Driver'), findsOneWidget);
    expect(find.textContaining('901234567V'), findsNothing);
    expect(find.textContaining('B1234567'), findsNothing);
  });

  testWidgets('Late results after disposal cannot show previous private driver data', (tester) async {
    final pending = Completer<DriverAdministration>();
    final service = _DriverService(data())..pending = pending.future;
    await _panel(tester, service);
    expect(find.bySemanticsLabel('Loading driver administration'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    pending.complete(data()); await pump(tester);
    expect(find.textContaining('NIC:'), findsNothing); expect(tester.takeException(), isNull);
  });

  testWidgets('Failed private load hides raw errors and retry recovers driver details', (tester) async {
    final pending = Completer<DriverAdministration>();
    final service = _DriverService(data())..pending = pending.future;
    await _panel(tester, service);
    expect(find.bySemanticsLabel('Loading driver administration'), findsOneWidget);
    pending.completeError(StateError('sensitive backend detail'));
    await pump(tester);
    expect(find.text('Retry driver details'), findsOneWidget);
    expect(find.textContaining('sensitive backend detail'), findsNothing);
    service.pending = null;
    await tester.tap(find.text('Retry driver details')); await pump(tester);
    expect(service.loads, 2);
    expect(find.text('Identity status: pending'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Queued result keeps review controls disabled until refresh confirms completion', (tester) async {
    final initial = data();
    final service = _DriverService(DriverAdministration(profile: initial.profile, identity: initial.identity,
      payments: initial.payments, operations: [DriverRecord('queued', {'action': 'verify_identity', 'status': 'pending'})]));
    await _panel(tester, service);
    final verify = find.byKey(const ValueKey('verify_identity'));
    await reveal(tester, verify);
    expect(tester.widget<OutlinedButton>(verify).onPressed, isNull);
    expect(service.calls, isEmpty);
    service.current = data(identity: 'verified');
    final refresh = find.widgetWithIcon(IconButton, Icons.refresh);
    await tester.ensureVisible(refresh); await tester.pumpAndSettle();
    await tester.tap(refresh); await pump(tester);
    expect(find.text('Identity status: verified'), findsOneWidget);
    expect(find.textContaining('An operation is queued.'), findsNothing);
  });

  testWidgets('Founding quote remains visible as lifetime for registration above 100', (tester) async {
    final service = _DriverService(data(identity: 'verified', payment: 'verified', extra: {
      'driverRegistrationNumber': 103, 'membershipPlan': 'founding_lifetime', 'membershipStatus': 'active',
      'registrationFeePaidLkr': 3500, 'annualRenewalRequired': false, 'annualRenewalFeeLkr': null,
      'membershipValidUntil': null,
    }));
    await _panel(tester, service);
    for (final label in ['Quoted registration fee (LKR): 3500', 'Quoted membership plan: founding_lifetime',
      'Quoted annual renewal required: No', 'Registration number: 103', 'Plan: founding_lifetime',
      'Annual renewal required: No', 'Valid until: Lifetime — no expiry']) {
      await reveal(tester, find.text(label));
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stage 11A/B/C dashboard navigation entries remain', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(service: _Admin()))); await pump(tester);
    expect(find.byKey(const Key('admin_users_entry')), findsOneWidget);
    expect(find.byKey(const Key('admin_support_entry')), findsOneWidget);
    expect(find.text('Operations overview'), findsOneWidget);
  });
}

class _Admin extends AdminService {
  bool allowed = true;
  String type = 'driver';
  @override
  Future<AdminAccess> readAccess({bool forceRefresh = false}) async => AdminAccess(
    allowed ? AdminAccessStatus.allowed : AdminAccessStatus.denied, uid: 'admin');
  @override
  Stream<AdminAccess> watchAccess() => Stream.fromFuture(readAccess());
  @override
  Future<AdminUserSummary?> loadUser(String uid) async => AdminUserSummary(uid: uid, accountType: type, fullName: 'Account');
  @override
  Future<AdminDashboardData> loadDashboard() async => const AdminDashboardData(stats: AdminDashboardStats(
    totalUsers: 1, totalDrivers: 1, totalTourists: 0, totalTrips: 0, openTrips: 0, activeTrips: 0,
    completedTrips: 0, openSupportRequests: 0), recentSupport: []);
}
class _ListAdmin extends _Admin {
  @override
  Future<AdminUserPage> loadUsers({AdminUserFilter filter = AdminUserFilter.all, String? afterUid}) async =>
    AdminUserPage(users: [AdminUserSummary.fromMap('driver', {'fullName': 'Test Driver', 'accountType': 'driver',
      'nicNumber': '901234567V', 'drivingLicenceNumber': 'B1234567'})]);
}

class _OwnerService extends DriverAdministrationService {
  _OwnerService({required super.dataSource});
  @override
  Future<String> access(String uid, bool admin) async {
    if (admin || uid != 'driver') { throw StateError('Owner only'); }
    return 'driver';
  }
}

class _DriverService extends DriverAdministrationService {
  _DriverService(this.current);
  DriverAdministration current;
  Future<DriverAdministration>? pending;
  Object? submissionError;
  int loads = 0, ids = 0;
  final calls = <Map<String, dynamic>>[];
  @override
  Stream<String?> watchOwner() => Stream.value('driver');
  @override
  Future<DriverAdministration> load(String uid, {required bool admin}) async { loads++; return pending == null ? current : await pending!; }
  @override
  String newOperationId(String uid) => 'operation-${++ids}';
  @override
  Future<void> perform(String uid, String action, Map<String, dynamic> payload,
      {required bool admin, required int revision, required String operationId, String reason = ''}) async {
    calls.add({'uid': uid, 'action': action, 'payload': payload, 'admin': admin, 'revision': revision,
      'operationId': operationId, 'reason': reason});
    final error = submissionError;
    if (error != null) { throw error; }
    if (action == 'submit_identity') {
      current = DriverAdministration(profile: {...current.profile, 'identityVerificationStatus': 'pending', 'driverAdminRevision': revision + 1},
        identity: DriverRecord(uid, {...payload, 'identityVerificationStatus': 'pending'}),
        payments: current.payments, history: current.history);
    }
  }
}
class _Source implements DriverAdministrationDataSource {
  int loads = 0;
  final commands = <Map<String, dynamic>>[];
  DriverRecord result = DriverRecord('op', {'status': 'succeeded'});
  @override
  Future<DriverAdministration> load(String uid, bool admin) async { loads++; return data(); }
  @override
  Future<List<DriverRecord>> page(String uid, String collection, DriverRecord after) async => [];
  @override
  String operationId(String uid) => 'op';
  @override
  Future<void> enqueue(String uid, String operationId, Map<String, dynamic> command) async { commands.add(command); }
  @override
  Stream<DriverRecord> watchOperation(String uid, String operationId) => Stream.value(result);
}
