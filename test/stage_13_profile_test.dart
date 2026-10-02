import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/account_profile.dart';
import 'package:taxi_app/core/services/auth_service.dart';
import 'package:taxi_app/core/services/profile_service.dart';
import 'package:taxi_app/screens/auth/profile_settings_screen.dart';

class _Session implements ProfileSession {
  @override
  String? uid = 'owner';
  @override
  String? email = 'login@example.test';
  final controller = StreamController<String?>.broadcast(sync: true);
  int reauthCalls = 0;
  Object? error;
  Completer<void>? reauthGate;
  @override
  Stream<String?> get changes => controller.stream;
  @override
  Future<void> reauthenticate(String uid, String password) async {
    reauthCalls++;
    if (error != null) {
      throw error!;
    }
    if (reauthGate != null) {
      await reauthGate!.future;
    }
  }
  void switchTo(String? next) {
    uid = next;
    controller.add(next);
  }
}

class _Store implements ProfileStore {
  Map<String, dynamic> data = {
    'fullName': 'Test Applicant', 'phoneNumber': '+94771234567', 'city': 'Kandy',
    'email': 'old-profile@example.test', 'accountType': 'tourist',
    'registrationStatus': 'approved', 'accountStatus': 'active',
  };
  final writes = <Map<String, String>>[];
  final loadedUids = <String>[];
  Object? writeError;
  Completer<Map<String, dynamic>?>? loadGate;
  @override
  Future<Map<String, dynamic>?> load(String uid) async {
    loadedUids.add(uid);
    if (loadGate != null) {
      return await loadGate!.future;
    }
    return Map.of(data);
  }
  void _write(String uid, Map<String, String> patch) {
    if (writeError != null) {
      throw writeError!;
    }
    expect(uid, 'owner');
    writes.add(patch);
    data.addAll(patch);
  }
  @override
  Future<void> updateDetails(String uid, {required String fullName, required String city}) async =>
    _write(uid, {'fullName': fullName, 'city': city});
  @override
  Future<void> updatePhone(String uid, String phoneNumber) async =>
    _write(uid, {'phoneNumber': phoneNumber});
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 180,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

void main() {
  late _Session session;
  late _Store store;
  late ProfileService service;
  setUp(() {
    session = _Session(); store = _Store();
    service = ProfileService(session: session, store: store);
  });
  tearDown(() async {
    service.dispose();
    await session.controller.close();
  });

  test('own profile uses Auth email and details update has a fixed field boundary', () async {
    final profile = await service.load();
    expect(profile.loginEmail, 'login@example.test');
    expect(store.loadedUids, ['owner']);
    await service.updateDetails(fullName: ' Updated Name ', city: ' Galle ');
    expect(store.writes.single, {'fullName': 'Updated Name', 'city': 'Galle'});
    expect(session.reauthCalls, 0);
    expect(store.data['accountType'], 'tourist');
    expect(store.data['registrationStatus'], 'approved');
  });
  test('phone requires a password and wrong password cannot write', () async {
    await expectLater(service.changePhone(phoneNumber: '+94777654321', password: ''), throwsA(isA<ProfileException>()));
    expect(session.reauthCalls, 0);
    session.error = const AuthServiceException(code: 'wrong-password', message: 'The email or password is incorrect.');
    await expectLater(service.changePhone(phoneNumber: '+94777654321', password: 'incorrect'), throwsA(isA<AuthServiceException>()));
    expect(session.reauthCalls, 1);
    expect(store.writes, isEmpty);
  });
  test('successful reauthentication precedes phone-only update', () async {
    session.reauthGate = Completer<void>();
    final pending = service.changePhone(phoneNumber: ' +94777654321 ', password: 'test-password');
    expect(session.reauthCalls, 1);
    expect(store.writes, isEmpty);
    session.reauthGate!.complete();
    await pending;
    expect(store.writes.single, {'phoneNumber': '+94777654321'});
    expect(store.data['email'], 'old-profile@example.test');
  });
  test('account switch during reauthentication prevents any profile write', () async {
    session.reauthGate = Completer<void>();
    final pending = service.changePhone(phoneNumber: '+94777654321', password: 'test-password');
    final assertion = expectLater(pending, throwsA(isA<ProfileException>()));
    session.switchTo('other');
    session.switchTo('owner');
    session.reauthGate!.complete();
    await assertion;
    expect(store.writes, isEmpty);
  });
  test('logout denies load/edit and invalid input cannot save', () async {
    await expectLater(service.updateDetails(fullName: ' ', city: ''), throwsA(isA<ProfileException>()));
    await expectLater(service.changePhone(phoneNumber: 'abc', password: 'test'), throwsA(isA<ProfileException>()));
    session.switchTo(null);
    await expectLater(service.load(), throwsA(isA<ProfileException>()));
    await expectLater(service.updateDetails(fullName: 'Name', city: ''), throwsA(isA<ProfileException>()));
    expect(store.writes, isEmpty);
  });
  test('legacy and absent optional values remain safe', () {
    final legacy = AccountProfile({'accountType': 'driver', 'status': 'active',
      'membershipValidUntil': 'malformed'}, loginEmail: null);
    expect(legacy.registrationStatus, 'Legacy account');
    expect(legacy.accountStatus, 'active');
    expect(legacy.registrationNumber, 'Not assigned');
    expect(legacy.membershipExpiry, 'Not available');
  });
  test('malformed existing upgrade summary never offers another new request', () {
    final profile = AccountProfile({...store.data, 'status': 'active', 'driverUpgradeStatus': 42}, loginEmail: session.email);
    expect(profile.canRequestDriverUpgrade, isFalse);
  });
  for (final activated in [false, true]) {
    testWidgets('approved upgrade displays ${activated ? 'active membership' : 'remaining activation'} from trusted state', (tester) async {
      store.data.addAll({'status': 'active', 'accountType': 'driver', 'driverUpgradeStatus': 'approved',
        'registrationStatus': 'approved', 'identityVerificationStatus': 'verified',
        'paymentStatus': activated ? 'verified' : 'pending', 'membershipStatus': activated ? 'active' : 'pending',
        'accountStatus': activated ? 'active' : 'pending_approval', 'membershipPlan': 'founding_lifetime'});
      await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
      await tester.pump();
      final label = activated ? 'Driver upgrade approved — driver membership active' : 'Approved — payment/membership activation required';
      await reveal(tester, find.text(label)); expect(find.text(label), findsOneWidget);
    });
  }
  for (final width in [360.0, 1400.0]) {
    testWidgets('driver trusted fields are read-only at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.data.addAll({'accountType': 'driver', 'driverRegistrationNumber': 101,
        'identityVerificationStatus': 'verified', 'paymentStatus': 'verified',
        'membershipStatus': 'active', 'membershipPlan': 'standard_annual',
        'membershipValidUntil': Timestamp.fromDate(DateTime.utc(2030, 1, 1)),
        'vehicleType': 'Sedan Car', 'vehicleNumber': 'TEST-1234', 'operatingArea': 'Kandy'});
      await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
      await tester.pump();
      expect(find.text('Test Applicant'), findsWidgets);
      await reveal(tester, find.text('login@example.test'));
      expect(find.text('old-profile@example.test'), findsNothing);
      await reveal(tester, find.text('Driver registration number'));
      expect(find.text('101'), findsOneWidget);
      expect(find.text('standard annual'), findsOneWidget);
      await reveal(tester, find.text('Operating area'));
      expect(find.byType(TextFormField), findsNothing);
      for (final label in ['Grant admin', 'Verify identity', 'Activate membership', 'Delete account', 'Change account type']) {
        expect(find.text(label), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('tourist sees own profile and edits only personal details', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
    await tester.pump();
    expect(find.text('Tourist / User'), findsOneWidget);
    expect(find.text('Driver membership & vehicle'), findsNothing);
    await reveal(tester, find.text('Edit personal details'));
    await tester.tap(find.text('Edit personal details'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byKey(const Key('profile_name')), 'New Name');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(store.writes.single, {'fullName': 'New Name', 'city': 'Kandy'});
    expect(find.text('Profile updated.'), findsOneWidget);
  });
  testWidgets('phone dialog validates, displays wrong-password/write errors and cancels safely', (tester) async {
    await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
    await tester.pump();
    await reveal(tester, find.text('Change phone number'));
    await tester.tap(find.text('Change phone number'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm change'));
    await tester.pump();
    expect(find.text('Phone number is required.'), findsOneWidget);
    expect(find.text('Enter your current password.'), findsOneWidget);
    session.error = const AuthServiceException(code: 'wrong-password', message: 'The email or password is incorrect.');
    await tester.enterText(find.byKey(const Key('profile_phone')), '+94777654321');
    await tester.enterText(find.byKey(const Key('profile_password')), 'incorrect');
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(find.text('The email or password is incorrect.'), findsOneWidget);
    expect(store.writes, isEmpty);
    session.error = null;
    store.writeError = FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await tester.enterText(find.byKey(const Key('profile_password')), 'test-password');
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This change was not permitted'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.writes, isEmpty);
  });
  testWidgets('loading and failure retry are visible; logout hides profile', (tester) async {
    store.loadGate = Completer<Map<String, dynamic>?>();
    await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    store.loadGate!.completeError(const ProfileException('Profile unavailable.'));
    await tester.pump();
    expect(find.text('Profile unavailable.'), findsOneWidget);
    store.loadGate = null;
    await tester.tap(find.text('Retry'));
    // Attach the replacement future, then render its completion on the next frame.
    await tester.pump();
    await tester.pump();
    expect(find.text('Test Applicant'), findsWidgets);
    session.switchTo(null);
    await tester.pump();
    expect(find.text('Test Applicant'), findsNothing);
    expect(find.text('Sign in again to view your profile.'), findsOneWidget);
  });
  testWidgets('successful phone confirmation saves and email stays literal/read-only', (tester) async {
    session.email = 'first_last@example.test';
    await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
    await tester.pump();
    await reveal(tester, find.text('first_last@example.test'));
    expect(find.byType(TextFormField), findsNothing);
    await reveal(tester, find.text('Change phone number'));
    await tester.tap(find.text('Change phone number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_phone')), '+94777654321');
    await tester.enterText(find.byKey(const Key('profile_password')), 'test-password');
    await tester.tap(find.text('Confirm change'));
    await tester.pumpAndSettle();
    expect(session.reauthCalls, 1);
    expect(store.writes.single, {'phoneNumber': '+94777654321'});
    expect(find.text('Phone number updated.'), findsOneWidget);
  });
  testWidgets('switch during open confirmation dismisses only the dialog and prevents save', (tester) async {
    session.reauthGate = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
    await tester.pump();
    await reveal(tester, find.text('Change phone number'));
    await tester.tap(find.text('Change phone number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile_phone')), '+94777654321');
    await tester.enterText(find.byKey(const Key('profile_password')), 'test-password');
    await tester.tap(find.text('Confirm change'));
    await tester.pump();
    session.switchTo(null);
    session.switchTo('other');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    expect(find.text('Sign in again to view your profile.'), findsOneWidget);
    session.reauthGate!.complete();
    await tester.pump();
    expect(store.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('signed-out entry never loads a private profile', (tester) async {
    session.switchTo(null);
    await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
    await tester.pump();
    expect(store.loadedUids, isEmpty);
    expect(find.text('Sign in again to view your profile.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final accountType in ['tourist', 'driver']) {
    testWidgets('$accountType profile shows the upgrade entry only for eligible Tourists', (tester) async {
      store.data.addAll({'status': 'active', 'accountType': accountType});
      await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
      await tester.pump();
      if (accountType == 'tourist') {
        await reveal(tester, find.text('Become a Driver / Partner'));
        expect(find.text('Become a Driver / Partner'), findsOneWidget);
      } else {
        await reveal(tester, find.text('Driver registration number'));
        expect(find.text('Become a Driver / Partner'), findsNothing);
      }
    });
  }
  for (final status in ['draft', 'pending_review', 'correction_required', 'rejected', 'approved']) {
    testWidgets('existing upgrade $status shows status instead of duplicate entry', (tester) async {
      store.data.addAll({'status': 'active', 'driverUpgradeStatus': status});
      await tester.pumpWidget(MaterialApp(home: ProfileSettingsScreen(service: service)));
      await tester.pump();
      await reveal(tester, find.text('View driver upgrade'));
      expect(find.text('Become a Driver / Partner'), findsNothing);
      expect(find.text(status == 'approved' ? 'Approved — payment/membership activation required'
        : 'Driver upgrade: ${status.replaceAll('_', ' ')}'), findsOneWidget);
    });
  }
}
