import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_selector/file_selector.dart';
import 'evidence_image_service.dart';

class SelectedEvidence {
  const SelectedEvidence(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

class DriverEvidenceService {
  DriverEvidenceService({FirebaseAuth? auth, FirebaseStorage? storage, this.registrationApplication = false, this.paymentId}) : _authOverride = auth, _storageOverride = storage;
  final bool registrationApplication;
  final String? paymentId;
  final FirebaseAuth? _authOverride;
  final FirebaseStorage? _storageOverride;
  String? _debugReviewClaimUid;
  bool? _debugReviewAdminClaim;
  String _debugReviewStage = 'not_started';
  FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  bool get mobileCapture => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  static bool requiresCamera(EvidenceType type, {required bool mobile}) => mobile && type == EvidenceType.selfie;
  Future<SelectedEvidence?> selectFor(EvidenceType type, {bool camera = false}) async {
    if (!mobileCapture || (!camera && !requiresCamera(type, mobile: mobileCapture))) { return select(); }
    return capture(type);
  }
  Future<SelectedEvidence?> capture(EvidenceType type) async {
    // Never fall back to gallery when a mobile selfie capture fails or is cancelled.
    final file = await ImagePicker().pickImage(source: ImageSource.camera,
      preferredCameraDevice: type == EvidenceType.selfie ? CameraDevice.front : CameraDevice.rear,
      requestFullMetadata: false);
    if (file == null) { return null; }
    if (await file.length() > const EvidenceImagePolicy().inputBytes) {
      throw const EvidenceImageException('This image is too large. Please take another photo.');
    }
    return SelectedEvidence(file.name, await file.readAsBytes());
  }

  Future<SelectedEvidence?> select() async {
    if (mobileCapture) {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
      if (file == null) { return null; }
      if (await file.length() > const EvidenceImagePolicy().inputBytes) {
        throw const EvidenceImageException('This image is too large. Please choose another photo.');
      }
      return SelectedEvidence(file.name, await file.readAsBytes());
    }
    const group = XTypeGroup(label: 'JPEG or PNG photos', extensions: ['jpg', 'jpeg', 'png'],
      mimeTypes: ['image/jpeg', 'image/png'], uniformTypeIdentifiers: ['public.jpeg', 'public.png']);
    final file = await openFile(acceptedTypeGroups: [group]);
    if (file == null) { return null; }
    if (await file.length() > const EvidenceImagePolicy().inputBytes) {
      throw const EvidenceImageException('This image is too large. Please choose or take another photo.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > const EvidenceImagePolicy().inputBytes) {
      throw const EvidenceImageException('This image is too large. Please choose or take another photo.');
    }
    final basename = file.name.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'[\x00-\x1f]'), '');
    final name = basename.length <= 120 ? basename : 'Selected photo.${basename.split('.').last}';
    return SelectedEvidence(name, bytes);
  }

  Future<String> upload(String uid, int revision, EvidenceType type, PreparedEvidenceImage image,
      void Function(double) progress) async {
    if (_auth.currentUser?.uid != uid) { throw const EvidenceImageException('Sign in to your own account.'); }
    if (revision < 0 || uid.isEmpty || uid.contains('/') || image.bytes.isEmpty ||
        image.bytes.length > const EvidenceImagePolicy().limit(type) ||
        min(image.width, image.height) < 400 ||
        max(image.width, image.height) > (type == EvidenceType.selfie ? 1600 : 2000)) {
      throw const EvidenceImageException('This image cannot be uploaded. Please choose another photo.');
    }
    final random = Random.secure();
    final id = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    final namespace = registrationApplication ? 'registration_evidence' : 'driver_evidence';
    if (type == EvidenceType.paymentSlip && (paymentId == null || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(paymentId!))) {
      throw const EvidenceImageException('Refresh the payment request before uploading.');
    }
    final payment = type == EvidenceType.paymentSlip;
    final path = payment ? 'payment_evidence/$uid/$paymentId/$id.jpg' : '$namespace/$uid/$revision/${type.stored}/$id.jpg';
    final task = _storage.ref(path).putData(image.bytes, SettableMetadata(contentType: 'image/jpeg',
      cacheControl: 'private, no-store', customMetadata: {'ownerUid': uid, if (payment) 'paymentId': paymentId! else 'applicationRevision': '$revision',
        'evidenceType': type.stored, 'width': '${image.width}', 'height': '${image.height}'}));
    final subscription = task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) { progress(snapshot.bytesTransferred / snapshot.totalBytes); }
    }, onError: (Object _) {});
    try {
      await task;
      if (_auth.currentUser?.uid != uid) { throw const EvidenceImageException('Your session changed. Sign in again.'); }
      return path;
    } finally { await subscription.cancel(); }
  }

  Future<Uint8List> review(String uid, String path) async {
    if (kDebugMode) {
      _debugReviewClaimUid = null;
      _debugReviewAdminClaim = null;
      _debugReviewStage = 'auth_and_path_validation';
    }
    final user = _auth.currentUser;
    if (!validPath(uid, path)) { throw const EvidenceImageException('Invalid private photo reference. Refresh this record or contact support.'); }
    if (user == null) { throw const EvidenceImageException('Sign in again to view this private photo.'); }
    // Refresh before Storage obtains its bearer token; newly granted admin claims
    // must not be checked against the cached sign-in token.
    if (kDebugMode) {
      _debugReviewStage = 'refresh_auth_claims';
      debugPrint('[PrivateEvidenceTrace] beforeAuthRefresh');
    }
    final token = await user.getIdTokenResult(true);
    if (kDebugMode) {
      _debugReviewClaimUid = user.uid;
      _debugReviewAdminClaim = token.claims?['admin'] == true;
      _debugReviewStage = 'authorize_private_read';
      debugPrint('[PrivateEvidenceTrace] afterAuthRefresh admin=$_debugReviewAdminClaim');
    }
    if (user.uid != uid && token.claims?['admin'] != true) { throw const EvidenceImageException('Evidence access denied.'); }
    if (_auth.currentUser?.uid != user.uid) { throw const EvidenceImageException('Your session changed. Sign in again.'); }
    if (kDebugMode) {
      _debugReviewStage = 'storage_getData';
      debugPrint('[PrivateEvidenceTrace] beforeStorageRead');
    }
    final bytes = await _storage.ref(path).getData(2 * 1024 * 1024);
    if (kDebugMode) {
      _debugReviewStage = 'validate_downloaded_result';
      debugPrint('[PrivateEvidenceTrace] afterStorageRead bytes=${bytes?.length ?? "null"}');
    }
    if (_auth.currentUser?.uid != user.uid) { throw const EvidenceImageException('Your session changed. Sign in again.'); }
    if (bytes == null || bytes.isEmpty) { throw const EvidenceImageException('This photo is empty or unavailable. Ask the applicant to replace it.'); }
    return bytes;
  }

  // Includes failures opening the memory preview. No extra token requests.
  void debugReviewFailure(Object error, String path, {required String stage}) {
    if (!kDebugMode) { return; }
    try {
      debugPrint('[PrivateEvidenceTrace] caughtException stage=$stage');
      debugPrint('[PrivateEvidence] stage=$stage; fetchStage=$_debugReviewStage');
      debugPrint('[PrivateEvidence] exception.runtimeType=${error.runtimeType}');
      debugPrint('[PrivateEvidence] storagePath=$path');
      if (error is FirebaseException) {
        debugPrint('[PrivateEvidence] FirebaseException.code=${error.code}');
        debugPrint('[PrivateEvidence] FirebaseException.message=${_debugSafeMessage(error.message)}');
      }
      try {
        final user = _auth.currentUser;
        debugPrint('[PrivateEvidence] currentUser.exists=${user != null}');
        debugPrint('[PrivateEvidence] currentUser.uid=${user?.uid ?? "none"}');
        final claim = user != null && user.uid == _debugReviewClaimUid
            ? _debugReviewAdminClaim : null;
        debugPrint('[PrivateEvidence] refreshedClaim.admin=${claim ?? "unavailable"}');
      } catch (_) {
        // Firebase initialization failures/test overrides may have no Auth instance.
        debugPrint('[PrivateEvidence] currentUser.exists=unavailable');
        debugPrint('[PrivateEvidence] currentUser.uid=unavailable');
        debugPrint('[PrivateEvidence] refreshedClaim.admin=unavailable');
      }
    } catch (_) {
      // Diagnostics must never replace the original error or affect navigation.
    }
  }

  static String _debugSafeMessage(String? message) {
    if (message == null) { return 'none'; }
    // SDK errors can include request URLs/credentials. Never print those values.
    return message
        .replaceAll(RegExp(r'(?:https?|gs)://[^\s]+', caseSensitive: false), '[URL redacted]')
        .replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'), '[token redacted]')
        .replaceAll(RegExp(r'(?:bearer\s+|(?:token|secret|signature|authorization)\s*[=:]\s*)[^\s,;]+',
            caseSensitive: false), '[credential redacted]');
  }

  static String reviewError(Object error) {
    if (error is EvidenceImageException) { return error.message; }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unauthorized':
        case 'permission-denied':
          return 'Access denied. This private photo is available only to its owner and a primary admin.';
        case 'unauthenticated':
        case 'user-token-expired':
          return 'Your session expired. Sign in again to view this private photo.';
        case 'object-not-found':
          return 'This photo was not found. Refresh the record or ask the applicant to upload it again.';
        case 'retry-limit-exceeded':
        case 'network-request-failed':
        case 'unavailable':
          return 'Could not download the photo. Check your connection and try again.';
        case 'download-size-exceeded':
          return 'This photo exceeds the private preview size limit.';
        default:
          return 'Could not load this private photo (${error.code}). Try again or contact support.';
      }
    }
    return 'Could not display this private photo. Try again or contact support.';
  }

  static bool validPath(String uid, String path) => uid.isNotEmpty && !uid.contains('/') &&
    (RegExp('^(driver_evidence|registration_evidence)/${RegExp.escape(uid)}/[0-9]+/(nic|driving_licence|selfie)/[a-f0-9]{32}\\.jpg\$').hasMatch(path) ||
      RegExp('^payment_evidence/${RegExp.escape(uid)}/[A-Za-z0-9_-]{1,128}/[a-f0-9]{32}\\.jpg\$').hasMatch(path));
}
