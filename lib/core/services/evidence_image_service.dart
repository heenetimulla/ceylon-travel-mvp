import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

enum EvidenceType {
  nic('NIC document'), drivingLicence('Driving licence document'), selfie('Selfie'), paymentSlip('Payment slip');
  const EvidenceType(this.label);
  final String label;
  String get stored => switch (this) { drivingLicence => 'driving_licence', paymentSlip => 'payment_slip', _ => name };
}

class EvidenceImageException implements Exception {
  const EvidenceImageException(this.message);
  final String message;
}

class EvidenceImagePolicy {
  const EvidenceImagePolicy({this.documentBytes = 2 * 1024 * 1024, this.selfieBytes = 1536 * 1024,
    this.inputBytes = 20 * 1024 * 1024, this.maxPixels = 24000000});
  final int documentBytes, selfieBytes, inputBytes, maxPixels;
  int limit(EvidenceType type) => type == EvidenceType.selfie ? selfieBytes : documentBytes;
  int longEdge(EvidenceType type) => type == EvidenceType.selfie ? 1600 : 2000;
}

class PreparedEvidenceImage {
  const PreparedEvidenceImage(this.bytes, this.width, this.height);
  final Uint8List bytes;
  final int width, height;
}

class EvidenceImageService {
  const EvidenceImageService({this.policy = const EvidenceImagePolicy()});
  final EvidenceImagePolicy policy;
  Future<PreparedEvidenceImage> prepare(Uint8List bytes, String name, EvidenceType type) =>
    compute(_prepareEvidence, (bytes, name, type, policy));
}

// Pure Dart: native compute uses an isolate; web executes locally on the UI thread.
// No file paths, network, EXIF/GPS metadata, or original bytes leave this function.
PreparedEvidenceImage _prepareEvidence((Uint8List, String, EvidenceType, EvidenceImagePolicy) input) {
  final (bytes, name, type, policy) = input;
  const unsupported = EvidenceImageException('Choose a JPEG or PNG photo. HEIC, PDF and archive files are not supported.');
  const tooLarge = EvidenceImageException('This image is too large. Please choose or take another photo.');
  try {
    if (bytes.isEmpty || bytes.length > policy.inputBytes) { throw tooLarge; }
    final ext = name.toLowerCase().split('.').last;
    final jpeg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
    final png = bytes.length > 8 && listEquals(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    if (!(jpeg && ['jpg', 'jpeg'].contains(ext)) && !(png && ext == 'png')) { throw unsupported; }
    final img.Decoder decoder = jpeg ? img.JpegDecoder() : img.PngDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null || info.width <= 0 || info.height <= 0 || info.numFrames > 1) { throw unsupported; }
    if (info.width * info.height > policy.maxPixels || math.max(info.width, info.height) > 12000) { throw tooLarge; }
    final decoded = decoder.decodeFrame(0);
    if (decoded == null) { throw const EvidenceImageException('This photo could not be opened. Please choose another photo.'); }
    var oriented = img.bakeOrientation(decoded);
    final edge = math.max(oriented.width, oriented.height);
    if (math.min(oriented.width, oriented.height) < 400 || edge < (type == EvidenceType.selfie ? 600 : 800)) {
      throw const EvidenceImageException('This photo is too small to review clearly. Please take a clearer photo.');
    }
    if (edge > policy.longEdge(type)) {
      final scale = policy.longEdge(type) / edge;
      oriented = img.copyResize(oriented, width: (oriented.width * scale).round(),
        height: (oriented.height * scale).round(), interpolation: img.Interpolation.average);
    }
    if (math.min(oriented.width, oriented.height) < 400) {
      throw const EvidenceImageException('This photo is too narrow to review clearly. Please take a closer photo.');
    }
    // Fresh RGB canvas strips EXIF/GPS, PNG text and original filenames; flatten transparency on white.
    final clean = img.Image(width: oriented.width, height: oriented.height, numChannels: 3);
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, oriented);
    // Keep resolution and 4:4:4 colour detail. Never chase the size cap with unreadable low quality.
    for (final quality in [85, 80]) {
      final output = img.encodeJpg(clean, quality: quality, chroma: img.JpegChroma.yuv444);
      if (output.length <= policy.limit(type)) { return PreparedEvidenceImage(output, clean.width, clean.height); }
    }
    throw tooLarge;
  } on EvidenceImageException { rethrow; }
  catch (_) { throw const EvidenceImageException('This photo could not be prepared. Please choose or take another photo.'); }
}
