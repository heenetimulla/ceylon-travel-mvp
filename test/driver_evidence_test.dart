import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:taxi_app/core/services/evidence_image_service.dart';
import 'package:taxi_app/core/services/driver_evidence_service.dart';
import 'package:taxi_app/core/services/driver_administration_service.dart';
import 'package:taxi_app/core/widgets/driver_evidence_widgets.dart';

Uint8List _png(int width, int height) => img.encodePng(img.Image(width: width, height: height));
const _path = 'driver_evidence/driver/4/nic/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';

void main() {
  test('Private review refreshes auth and preserves distinct safe failure messages', () async {
    final user = _User('admin', {'admin': true}, cachedClaims: {});
    for (final namespace in ['driver_evidence', 'registration_evidence']) {
      final storage = _Storage(Uint8List.fromList([1]));
      await DriverEvidenceService(auth: _Auth(user), storage: storage).review('driver', _path.replaceFirst('driver_evidence', namespace));
      expect(user.refreshed, isTrue);
      expect(storage.reads, 1);
      expect(storage.maximumBytes, 2 * 1024 * 1024);
    }
    for (final entry in {'unauthorized': 'Access denied', 'object-not-found': 'not found',
      'network-request-failed': 'connection', 'download-size-exceeded': 'size limit'}.entries) {
      expect(DriverEvidenceService.reviewError(FirebaseException(plugin: 'firebase_storage', code: entry.key)), contains(entry.value));
    }
    expect(DriverEvidenceService.reviewError(const EvidenceImageException('Invalid private photo reference.')), contains('Invalid'));
  });
  for (final type in EvidenceType.values) {
    testWidgets('Mobile source choices: ${type.stored}', (tester) async {
      final service = _SourcePicker();
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: DriverEvidenceUpload(uid: 'driver', revision: 1,
        type: type, enabled: true, service: service, onChange: (_) {}, onState: (_, _) {}))));
      if (type == EvidenceType.selfie) {
        expect(find.text('Choose from gallery'), findsNothing);
        await tester.tap(find.text('Take selfie')); await tester.pump();
      } else {
        await tester.tap(find.text('Choose from gallery')); await tester.pump();
        expect(service.selections, 1);
        await tester.tap(find.text('Take photo')); await tester.pump();
      }
      expect(service.captures, [type]);
    });
  }

  test('Mobile selfie always captures; NIC and licence keep normal selection; payment permits either', () async {
    final picker = _SourcePicker();
    await picker.selectFor(EvidenceType.selfie);
    expect(picker.captures, [EvidenceType.selfie]); expect(picker.selections, 0);
    await picker.selectFor(EvidenceType.nic); await picker.selectFor(EvidenceType.drivingLicence);
    await picker.selectFor(EvidenceType.paymentSlip);
    expect(picker.selections, 3);
    await picker.selectFor(EvidenceType.paymentSlip, camera: true);
    expect(picker.captures.last, EvidenceType.paymentSlip);
    picker.mobile = false;
    await picker.selectFor(EvidenceType.selfie);
    expect(picker.selections, 4);
  });
  test('Private payment paths enforce the owner and primary admin review boundary', () async {
    const path = 'payment_evidence/driver/payment/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.jpg';
    expect(DriverEvidenceService.validPath('driver', path), isTrue);
    expect(DriverEvidenceService.validPath('other', path), isFalse);
    for (final claims in <Map<String, dynamic>>[{}, {'supportAdmin': true}]) {
      final storage = _Storage(Uint8List(1));
      final service = DriverEvidenceService(auth: _Auth(_User('other', claims)), storage: storage, paymentId: 'payment');
      await expectLater(service.review('driver', path), throwsA(isA<EvidenceImageException>()));
      await expectLater(service.upload('driver', 0, EvidenceType.paymentSlip, PreparedEvidenceImage(Uint8List(10), 800, 600), (_) {}),
        throwsA(isA<EvidenceImageException>()));
      expect(storage.reads, 0);
    }
    final storage = _Storage(Uint8List.fromList([1, 2]));
    expect(await DriverEvidenceService(auth: _Auth(_User('admin', {'admin': true})), storage: storage).review('driver', path), [1, 2]);
    expect(const EvidenceImagePolicy().limit(EvidenceType.paymentSlip), 2097152);
    expect(const EvidenceImagePolicy().longEdge(EvidenceType.paymentSlip), 2000);
  });
  test('Large dimensions are resized locally and JPEG output remains inside the configured cap', () async {
    final result = await const EvidenceImageService().prepare(_png(2600, 1800), 'camera.png', EvidenceType.nic);
    expect(result.width, 2000); expect(result.height, 1385);
    expect(result.bytes.length, lessThanOrEqualTo(2097152));
    final decoded = img.decodeJpg(result.bytes)!;
    expect(decoded.width, 2000); expect(decoded.exif.hasTag(0x8825), isFalse);
  });
  test('Selfie uses 1600 pixels and its smaller byte ceiling', () async {
    final result = await const EvidenceImageService().prepare(_png(1800, 2400), 'selfie.png', EvidenceType.selfie);
    expect(result.height, 1600); expect(result.bytes.length, lessThanOrEqualTo(1572864));
  });
  test('Re-encoding removes camera metadata instead of carrying it into private evidence', () async {
    final original = img.Image(width: 1000, height: 700);
    original.exif.imageIfd[0x010f] = img.IfdValueAscii('Private camera');
    final input = img.encodeJpg(original);
    expect(img.decodeJpg(input)!.exif.hasTag(0x010f), isTrue);
    final result = await const EvidenceImageService().prepare(input, 'photo.jpg', EvidenceType.nic);
    expect(img.decodeJpg(result.bytes)!.exif.hasTag(0x010f), isFalse);
  });
  test('Oversized input/output and insufficient resolution fail without destructive size reduction', () async {
    await expectLater(const EvidenceImageService(policy: EvidenceImagePolicy(inputBytes: 10))
      .prepare(Uint8List(11), 'photo.jpg', EvidenceType.nic), throwsA(isA<EvidenceImageException>()));
    await expectLater(const EvidenceImageService(policy: EvidenceImagePolicy(documentBytes: 100))
      .prepare(_png(1000, 700), 'photo.png', EvidenceType.nic), throwsA(isA<EvidenceImageException>()));
    await expectLater(const EvidenceImageService().prepare(_png(100, 100), 'tiny.png', EvidenceType.nic),
      throwsA(isA<EvidenceImageException>()));
  });
  test('Archives, HEIC, extension/content mismatches and malformed files are rejected', () async {
    for (final name in ['photo.heic', 'photo.exe', 'photos.zip', 'photo.jpg']) {
      await expectLater(const EvidenceImageService().prepare(_png(1000, 700), name, EvidenceType.nic),
        throwsA(isA<EvidenceImageException>()));
    }
    await expectLater(const EvidenceImageService().prepare(Uint8List.fromList([255, 216, 255]), 'bad.jpg', EvidenceType.nic),
      throwsA(isA<EvidenceImageException>()));
  });
  test('Applicant cannot upload to another user path before any Storage call', () async {
    final storage = _Storage(Uint8List(0));
    final service = DriverEvidenceService(auth: _Auth(_User('driver', {})), storage: storage);
    await expectLater(service.upload('other', 4, EvidenceType.nic, PreparedEvidenceImage(Uint8List(10), 800, 600), (_) {}),
      throwsA(isA<EvidenceImageException>()));
    expect(storage.reads, 0);
  });
  test('Primary admin can review privately; other ordinary/support users cannot', () async {
    for (final claims in <Map<String, dynamic>>[{}, {'supportAdmin': true}, {'admin': 'true'}]) {
      final storage = _Storage(Uint8List(10));
      await expectLater(DriverEvidenceService(auth: _Auth(_User('other', claims)), storage: storage).review('driver', _path),
        throwsA(isA<EvidenceImageException>()));
      expect(storage.reads, 0);
    }
    final storage = _Storage(Uint8List.fromList([1, 2]));
    expect(await DriverEvidenceService(auth: _Auth(_User('admin', {'admin': true})), storage: storage).review('driver', _path), [1, 2]);
    expect(storage.reads, 1);
    expect(DriverEvidenceService.validPath('other', _path), isFalse);
  });
  test('Evidence map retries compare contents, not Dart map identity', () {
    final before = {'evidence': {'nic': _path}};
    expect(FirestoreDriverAdministrationDataSource.samePayload(before, {'evidence': {'nic': _path}}), isTrue);
    expect(FirestoreDriverAdministrationDataSource.samePayload(before, {'evidence': {'nic': 'different'}}), isFalse);
  });

  testWidgets('Preview requires readability confirmation; upload failure is friendly', (tester) async {
    final service = _Picker();
    final states = <bool>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DriverEvidenceUpload(
      uid: 'driver', revision: 4, type: EvidenceType.nic, enabled: true, service: service, images: _Images(),
      onChange: (_) {}, onState: (_, ready) => states.add(ready))))));
    await tester.tap(find.text('Choose photo')); await tester.pumpAndSettle();
    expect(find.text('Replace photo'), findsOneWidget); expect(find.text('Remove photo'), findsOneWidget);
    final upload = find.byKey(const ValueKey('upload_nic'));
    expect(tester.widget<FilledButton>(upload).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile)); await tester.pumpAndSettle();
    await tester.ensureVisible(upload); await tester.tap(upload); await tester.pumpAndSettle();
    expect(service.uploads, 1);
    expect(find.textContaining('Photo upload failed.'), findsOneWidget);
    expect(states.last, false);
    await tester.ensureVisible(find.text('Remove photo'));
    await tester.tap(find.text('Remove photo')); await tester.pumpAndSettle();
    expect(states.last, true);
  });
  testWidgets('Private viewer displays the real missing-photo error without public URLs', (tester) async {
    final service = DriverEvidenceService(auth: _Auth(_User('admin', {'admin': true})),
      storage: _Storage(Uint8List(0), error: FirebaseException(plugin: 'firebase_storage', code: 'object-not-found')));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DriverEvidenceReview(uid: 'driver', service: service,
      evidence: const [{'storagePath': _path, 'evidenceType': 'nic'}]))));
    await tester.tap(find.textContaining('View privately:')); await tester.pump(); await tester.pump();
    expect(find.textContaining('This photo was not found.'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });
  testWidgets('Preparation failure shows a useful message without uploading', (tester) async {
    final service = _Picker();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: DriverEvidenceUpload(uid: 'driver', revision: 4,
      type: EvidenceType.nic, enabled: true, service: service, images: _Images(fail: true), onChange: (_) {}, onState: (_, _) {}))));
    await tester.tap(find.text('Choose photo')); await tester.pumpAndSettle();
    expect(find.text('Please choose another photo.'), findsOneWidget);
    expect(service.uploads, 0);
  });
  testWidgets('Confirmed photo shows progress then ready; duplicate upload is unavailable', (tester) async {
    final service = _SuccessfulPicker();
    String? uploaded;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DriverEvidenceUpload(
      uid: 'driver', revision: 4, type: EvidenceType.nic, enabled: true, service: service, images: _Images(),
      onChange: (path) => uploaded = path, onState: (_, _) {})))));
    await tester.tap(find.text('Choose photo')); await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile)); await tester.pumpAndSettle();
    final upload = find.byKey(const ValueKey('upload_nic'));
    await tester.ensureVisible(upload); await tester.tap(upload); await tester.pump();
    expect(find.text('Uploading photo...'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, .5);
    expect(tester.widget<FilledButton>(upload).onPressed, isNull);
    service.completed.complete(_path); await tester.pumpAndSettle();
    expect(uploaded, _path);
    expect(find.textContaining('Uploaded — ready'), findsOneWidget);
    expect(upload, findsNothing);
  });
  testWidgets('Private review preview closes when its gated owner panel is removed', (tester) async {
    final visible = ValueNotifier(true);
    final service = DriverEvidenceService(auth: _Auth(_User('admin', {'admin': true})), storage: _Storage(_png(20, 20)));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ValueListenableBuilder<bool>(valueListenable: visible,
      builder: (_, show, _) => show ? DriverEvidenceReview(uid: 'driver', service: service,
        evidence: const [{'storagePath': _path, 'evidenceType': 'nic', 'width': 1000, 'height': 700}]) : const SizedBox()))));
    await tester.tap(find.textContaining('View privately:'));
    // The owner stays busy until the preview closes, so its indeterminate
    // progress indicator intentionally never settles while the dialog is open.
    await tester.pump();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    final previewRoute = ModalRoute.of(tester.element(find.byType(InteractiveViewer)))!;
    await tester.pump(previewRoute.transitionDuration);
    visible.value = false;
    await tester.pump(); // Dispose the owner and run its post-frame route removal.
    await tester.pump(); // Rebuild the overlay after removing the private route.
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(DriverEvidenceReview), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    visible.dispose();
  });
}

class _Images extends EvidenceImageService {
  _Images({this.fail = false});
  final bool fail;
  @override
  Future<PreparedEvidenceImage> prepare(Uint8List bytes, String name, EvidenceType type) async {
    if (fail) { throw const EvidenceImageException('Please choose another photo.'); }
    return PreparedEvidenceImage(_png(10, 10), 1000, 700);
  }
}
class _SourcePicker extends DriverEvidenceService {
  bool mobile = true;
  int selections = 0;
  final captures = <EvidenceType>[];
  @override
  bool get mobileCapture => mobile;
  @override
  Future<SelectedEvidence?> select() async { selections++; return null; }
  @override
  Future<SelectedEvidence?> capture(EvidenceType type) async { captures.add(type); return null; }
}
class _Picker extends DriverEvidenceService {
  @override
  bool get mobileCapture => false;
  int uploads = 0;
  @override
  Future<SelectedEvidence?> select() async => SelectedEvidence('photo.png', Uint8List(1));
  @override
  Future<String> upload(String uid, int revision, EvidenceType type, PreparedEvidenceImage image, void Function(double) progress) async {
    uploads++; throw StateError('private error');
  }
}
class _SuccessfulPicker extends _Picker {
  final completed = Completer<String>();
  @override
  Future<String> upload(String uid, int revision, EvidenceType type, PreparedEvidenceImage image, void Function(double) progress) {
    uploads++;
    progress(.5);
    return completed.future;
  }
}
class _Auth implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  final User? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _User implements User {
  _User(this.uid, this._claims, {this.cachedClaims});
  final Map<String, dynamic>? cachedClaims;
  @override
  final String uid;
  final Map<String, dynamic> _claims;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    refreshed = forceRefresh;
    return _Token(forceRefresh ? _claims : cachedClaims ?? _claims);
  }
  bool refreshed = false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Token implements IdTokenResult {
  _Token(this.claims);
  @override
  final Map<String, dynamic> claims;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Storage implements FirebaseStorage {
  _Storage(this.bytes, {this.error});
  final Uint8List bytes;
  final Object? error;
  int? maximumBytes;
  int reads = 0;
  @override
  Reference ref([String? path]) => _Reference(this);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Reference implements Reference {
  _Reference(this.storage);
  @override
  final _Storage storage;
  @override
  Future<Uint8List?> getData([int maxSize = 10485760]) async {
    storage.reads++; storage.maximumBytes = maxSize;
    if (storage.error != null) { throw storage.error!; }
    return storage.bytes;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
