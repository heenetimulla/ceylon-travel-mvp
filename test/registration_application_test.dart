import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:taxi_app/core/models/registration_application.dart';
import 'package:taxi_app/core/models/driver_administration.dart';
import 'package:taxi_app/core/models/admin_user_summary.dart';
import 'package:taxi_app/core/services/registration_application_service.dart';
import 'package:taxi_app/core/services/driver_evidence_service.dart';
import 'package:taxi_app/core/services/evidence_image_service.dart';
import 'package:taxi_app/core/widgets/registration_application_panel.dart';
import 'package:taxi_app/core/widgets/driver_evidence_widgets.dart';
import 'package:taxi_app/screens/auth/session_navigation.dart';
import 'package:taxi_app/screens/auth/registration_application_screen.dart';
import 'package:taxi_app/screens/tourist/tourist_home_screen.dart';

Map<String, dynamic> _profile({bool driver = false, String status = 'draft'}) => {
  'uid': 'owner', 'accountType': driver ? 'driver' : 'tourist', 'registrationStatus': status,
  'accountStatus': 'pending_approval', 'applicationRevision': 0, 'status': 'active',
  'fullName': 'Applicant', 'phoneNumber': '0771234567', 'city': 'Colombo', 'email': 'owner@example.com',
  if (driver) ...{'vehicleType': 'Small Car', 'vehicleNumber': 'ABC-1234', 'operatingArea': 'Colombo', 'availableAreas': 'Western'},
};
Widget _panel(_Service service, {bool admin = false}) => MaterialApp(home: Scaffold(body: SingleChildScrollView(
  child: RegistrationApplicationPanel(uid: 'owner', admin: admin, service: service, evidenceService: _Evidence(), images: _Images()))));
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder); await tester.pumpAndSettle(); await tester.tap(finder); await tester.pumpAndSettle();
}

void main() {
  test('Pending/rejected/correction accounts cannot operate; approved Tourist can', () {
    for (final status in ['draft', 'pending_review', 'correction_required', 'rejected']) {
      final data = {..._profile(status: status), 'accountStatus': 'active'};
      expect(applicationOperational(data), isFalse);
      expect(sessionDestination('owner', data), isA<RegistrationApplicationScreen>());
    }
    final approved = {..._profile(status: 'approved'), 'accountStatus': 'active'};
    expect(applicationOperational(approved), isTrue);
    expect(sessionDestination('owner', approved), isA<TouristHomeScreen>());
  });
  test('Driver identity approval alone cannot bypass payment/membership or inactivity', () {
    final data = {..._profile(driver: true, status: 'approved'), 'identityVerificationStatus': 'verified', 'accountStatus': 'active'};
    expect(applicationOperational(data), isFalse); expect(driverCanBid(data), isFalse);
    data.addAll({'paymentStatus': 'verified', 'membershipStatus': 'active', 'membershipPlan': 'founding_lifetime'});
    expect(applicationOperational(data), isTrue);
    data['accountStatus'] = 'inactive'; expect(applicationOperational(data), isFalse); expect(driverCanBid(data), isFalse);
  });
  test('Submission requires correct documents and explicit versioned agreement', () {
    expect(registrationAgreementVersion, '1.0');
    String? validate(bool driver, Map<String, String> evidence, bool agreement) => validateApplicationSubmission(
      driver: driver, nic: '901234567V', licence: 'B1234567', evidence: evidence, agreement: agreement);
    expect(validate(false, {'nic': 'private'}, true), isNotNull);
    expect(validate(false, {'nic': 'private', 'selfie': 'private'}, false), contains('Agreement'));
    expect(validate(false, {'nic': 'private', 'selfie': 'private'}, true), isNull);
    expect(validate(true, {'nic': 'private', 'selfie': 'private'}, true), isNotNull);
    expect(validate(true, {'nic': 'private', 'selfie': 'private', 'driving_licence': 'private'}, true), isNull);
  });
  for (final driver in [false, true]) {
    testWidgets('${driver ? 'Driver' : 'Tourist'} sees only required role-specific inputs and private uploads', (tester) async {
      await tester.pumpWidget(_panel(_Service(_profile(driver: driver)))); await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('application_nicNumber')), findsOneWidget);
      expect(find.byKey(const ValueKey('application_drivingLicenceNumber')), driver ? findsOneWidget : findsNothing);
      expect(find.byType(DriverEvidenceUpload), findsNWidgets(driver ? 3 : 2));
      expect(find.byKey(const ValueKey('registrationAgreement')), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('reviewApplication')));
      expect(find.text('Review application'), findsOneWidget); // button, no review dialog for invalid form
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
  for (final driver in [false, true]) {
  testWidgets('${driver ? 'Driver' : 'Tourist'} submits prepared required evidence and agreement through operation service', (tester) async {
    final service = _Service(_profile(driver: driver));
    await tester.pumpWidget(_panel(service)); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('application_nicNumber')));
    await tester.enterText(find.byKey(const ValueKey('application_nicNumber')), '901234567V');
    if (driver) {
      await tester.ensureVisible(find.byKey(const ValueKey('application_drivingLicenceNumber')));
      await tester.enterText(find.byKey(const ValueKey('application_drivingLicenceNumber')), 'B1234567');
    }
    for (final type in requiredApplicationEvidence(driver)) {
      await _tap(tester, find.byKey(ValueKey('choose_$type')));
      final card = find.byKey(ValueKey('application_0_$type'));
      await _tap(tester, find.descendant(of: card, matching: find.byType(CheckboxListTile)));
      await _tap(tester, find.byKey(ValueKey('upload_$type')));
    }
    await _tap(tester, find.byKey(const ValueKey('reviewApplication')));
    expect(find.text('Read and accept the Registration Guidelines & Agreement.'), findsOneWidget);
    expect(service.calls, isEmpty);
    await _tap(tester, find.byKey(const ValueKey('registrationAgreement')));
    await _tap(tester, find.byKey(const ValueKey('reviewApplication')));
    await _tap(tester, find.text('Submit Application'));
    expect(service.calls.single['action'], 'submit_application');
    final payload = service.calls.single['payload'] as Map;
    expect(payload['agreementVersion'], '1.0'); expect(payload['agreementAccepted'], isTrue);
    expect(payload.containsKey('agreementAcceptedAt'), isFalse);
    expect(payload.containsKey('drivingLicenceNumber'), driver);
    expect((payload['evidence'] as Map).values.every((p) => (p as String).startsWith('registration_evidence/owner/1/')), isTrue);
    expect(find.textContaining('Application submitted for manual review'), findsOneWidget);
    expect(find.byType(DriverEvidenceUpload), findsNothing);
    expect(find.byKey(const ValueKey('reviewApplication')), findsNothing);
    expect(service.calls, hasLength(1));
  });
  }
  testWidgets('Correction shows safe reason and requires fresh manual review', (tester) async {
    final service = _Service({..._profile(status: 'correction_required'), 'applicationRevision': 2},
      application: {'reason': 'Please retake the photo.', 'nicNumber': '901234567V'});
    await tester.pumpWidget(_panel(service)); await tester.pumpAndSettle();
    expect(find.text('Review reason: Please retake the photo.'), findsOneWidget);
    expect(find.text(registrationResubmissionMessage), findsOneWidget);
    expect(find.textContaining('901234567V'), findsNothing);
    expect(find.byKey(const ValueKey('application_2_nic')), findsOneWidget);
  });
  for (final admin in [false, true]) {
    testWidgets('Submitted history retains agreement and limits raw identity to private admin review ($admin)', (tester) async {
      final service = _Service({..._profile(status: 'pending_review'), 'applicationRevision': 1});
      service.history.add({'operationId': 'submitted', 'applicationRevision': 1,
        'action': 'application_submitted', 'previousValue': 'draft', 'newValue': 'pending_review', 'actorUid': 'owner'});
      service.submission = {'applicationRevision': 1, 'nicNumber': '901234567V', 'agreementVersion': '1.0'};
      await tester.pumpWidget(_panel(service, admin: admin)); await tester.pumpAndSettle();
      await _tap(tester, find.text('Application history'));
      await _tap(tester, find.text('application_submitted · revision 1'));
      expect(find.text('Submitted revision 1 (immutable)'), findsOneWidget);
      expect(find.textContaining('Agreement: 1.0'), findsOneWidget);
      expect(find.textContaining('901234567V'), admin ? findsOneWidget : findsNothing);
      expect(service.calls, isEmpty);
    });
  }
  for (final width in [360.0, 1400.0]) {
    testWidgets('Admin reviews Tourist privately at $width and requires rejection reason', (tester) async {
      tester.view.physicalSize = Size(width, 1000); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      final service = _Service(_profile(status: 'pending_review'), application: {'nicNumber': '901234567V', 'agreementVersion': '1.0'});
      await tester.pumpWidget(_panel(service, admin: true)); await tester.pumpAndSettle();
      expect(find.textContaining('nicNumber: 901234567V'), findsOneWidget);
      await _tap(tester, find.text('Reject application'));
      await _tap(tester, find.text('Confirm'));
      expect(find.text('A reason is required.'), findsOneWidget); expect(service.calls, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'Please provide clearer evidence.');
      await _tap(tester, find.text('Confirm'));
      expect(service.calls.single['action'], 'reject');
      expect(service.calls.single['reason'], 'Please provide clearer evidence.');
      expect(tester.takeException(), isNull);
    });
  }
  test('Normal admin summary does not search private identity/evidence', () {
    final user = AdminUserSummary.fromMap('owner', {..._profile(), 'nicNumber': '901234567V', 'drivingLicenceNumber': 'B1234567', 'evidence': 'private-secret'});
    expect(user.registrationStatus, 'draft');
    for (final value in ['901234567V', 'B1234567', 'private-secret']) { expect(user.matchesSearch(value), isFalse); }
  });
}
class _Service extends RegistrationApplicationService {
  _Service(this.profile, {this.application});
  Map<String, dynamic> profile;
  Map<String, dynamic>? application;
  final history = <Map<String, dynamic>>[];
  Map<String, dynamic> submission = {};
  final calls = <Map<String, dynamic>>[];
  @override
  Future<RegistrationApplicationData> load(String uid, {bool admin = false}) async => RegistrationApplicationData(profile, application, [], history: history);
  @override
  Future<Map<String, dynamic>> loadSubmission(String uid, int revision, {bool admin = false}) async => submission;
  @override
  String newOperationId(String uid) => 'operation';
  @override
  Future<void> perform(String uid, String action, Map<String, dynamic> payload,
    {required int revision, required String operationId, bool admin = false, String reason = ''}) async {
    calls.add({'action': action, 'payload': payload, 'revision': revision, 'reason': reason});
    profile = {...profile, 'registrationStatus': action == 'submit_application' ? 'pending_review' : 'rejected'};
  }
}
class _Evidence extends DriverEvidenceService {
  @override
  Future<SelectedEvidence?> selectFor(EvidenceType type, {bool camera = false}) => select();
  @override
  Future<SelectedEvidence?> select() async => SelectedEvidence('photo.png', Uint8List(1));
  @override
  Future<String> upload(String uid, int revision, EvidenceType type, PreparedEvidenceImage image, void Function(double) progress) async =>
    'registration_evidence/$uid/$revision/${type.stored}/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';
}
class _Images extends EvidenceImageService {
  @override
  Future<PreparedEvidenceImage> prepare(Uint8List bytes, String name, EvidenceType type) async =>
    PreparedEvidenceImage(img.encodePng(img.Image(width: 10, height: 10)), 1000, 700);
}
