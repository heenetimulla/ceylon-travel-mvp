import 'package:cloud_firestore/cloud_firestore.dart';
import 'account_attention.dart';

enum AdminUserFilter {
  all('All', null),
  tourist('Tourist/User', 'tourist'),
  driver('Driver', 'driver');

  const AdminUserFilter(this.label, this.accountType);
  final String label;
  final String? accountType;
}

/// Only the operational fields needed by Stage 11B are retained.
/// Missing metrics are unknown, not invented zeroes. The document ID is canonical.
class AdminUserSummary {
  const AdminUserSummary({required this.uid, this.fullName, this.email,
    this.phoneNumber, this.accountType, this.city, this.status,
    this.profilePhotoPath, this.completedTripsCount, this.cancelledTripsCount,
    this.cancellationRate, this.averageRating, this.ratingsCount,
    this.verificationStatus, this.registrationStatus, this.createdAt, this.updatedAt, this.operationalLabel});

  final String? operationalLabel;
  String get statusLabel => operationalLabel ?? (status ?? 'Unknown status').toUpperCase();

  final String uid;
  final String? fullName, email, phoneNumber, accountType, city, status,
    profilePhotoPath, verificationStatus, registrationStatus;
  final int? completedTripsCount, cancelledTripsCount, ratingsCount;
  final double? cancellationRate, averageRating;
  final DateTime? createdAt, updatedAt;

  factory AdminUserSummary.fromMap(String uid, Map<String, dynamic> data) {
    final verification = data['verification'];
    return AdminUserSummary(
      uid: uid, registrationStatus: _text(data['registrationStatus']), operationalLabel: accountStatusLabel(data),
      fullName: _text(data['fullName']), email: _text(data['email']),
      phoneNumber: _text(data['phoneNumber']), accountType: _text(data['accountType']),
      city: _text(data['city']), status: _text(data['status']),
      profilePhotoPath: _text(data['profilePhotoPath']),
      completedTripsCount: _count(data['completedTripsCount']),
      cancelledTripsCount: _count(data['cancelledTripsCount']),
      ratingsCount: _count(data['ratingsCount']),
      cancellationRate: _number(data['cancellationRate'], maximum: 100),
      averageRating: _number(data['averageRating'], maximum: 5),
      verificationStatus: _text(data['identityVerificationStatus']) ?? _text(data['verificationStatus']) ??
        (verification is Map ? _text(verification['status']) : null),
      createdAt: _date(data['createdAt']), updatedAt: _date(data['updatedAt']),
    );
  }

  String get displayName => fullName ?? 'Unnamed account';
  String get accountTypeLabel => switch (accountType) {
    'tourist' => 'Tourist/User', 'driver' => 'Driver', _ => 'Unknown',
  };
  String get cancellationRateLabel => cancellationRate == null
    ? 'Not available' : '${cancellationRate!.toStringAsFixed(1)}%';
  String get averageRatingLabel => averageRating == null
    ? 'Not available' : averageRating!.toStringAsFixed(1);

  bool matchesSearch(String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    if ([fullName, email, phoneNumber].any((value) =>
        value?.toLowerCase().contains(needle) ?? false)) {
      return true;
    }
    // Ignore phone punctuation only for queries consisting of phone characters.
    if (!RegExp(r'^[+\d\s().-]+$').hasMatch(needle)) {
      return false;
    }
    final digits = needle.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty &&
      (phoneNumber?.replaceAll(RegExp(r'\D'), '').contains(digits) ?? false);
  }

  static String? _text(Object? value) => value is String && value.trim().isNotEmpty
    ? value.trim() : null;
  static double? _number(Object? value, {double? maximum}) {
    if (value is! num || !value.isFinite || value < 0 ||
        (maximum != null && value > maximum)) {
      return null;
    }
    return value.toDouble();
  }
  static int? _count(Object? value) {
    final number = _number(value);
    return number != null && number == number.truncateToDouble() ? number.toInt() : null;
  }
  static DateTime? _date(Object? value) {
    // Timestamp.toDate() defaults to local time. Normalize the representation,
    // preserving the SDK's epoch/microsecond conversion and the original instant.
    if (value is Timestamp) {
      return value.toDate().toUtc();
    }
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is! String) {
      return null;
    }
    final text = value.trim();
    // Accept legacy ISO dates/times. Validate components because DateTime.parse
    // otherwise rolls malformed dates such as February 30 into the next month.
    final parts = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})(?:[Tt ](\d{2}):(\d{2})(?::(\d{2})(?:[.,]\d{1,9})?)?(?:[zZ]|[+-](\d{2})(?::?(\d{2}))?)?)?$',
    ).firstMatch(text);
    if (parts == null) {
      return null;
    }
    int component(int index) => int.parse(parts.group(index) ?? '0');
    final year = component(1), month = component(2), day = component(3);
    if (month < 1 || month > 12 || day < 1 ||
        day > DateTime.utc(year, month + 1, 0).day ||
        component(4) > 23 || component(5) > 59 || component(6) > 59 ||
        component(7) > 23 || component(8) > 59) {
      return null;
    }
    // Explicit offsets/Z preserve their instant. Zone-less legacy strings use
    // local time, matching a local DateTime input. The UI localizes for display.
    return DateTime.tryParse(text)?.toUtc();
  }
}

class AdminUserPage {
  AdminUserPage({required List<AdminUserSummary> users, this.nextUid})
    : users = List.unmodifiable(users);
  final List<AdminUserSummary> users;
  final String? nextUid;
}
