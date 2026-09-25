import 'package:cloud_firestore/cloud_firestore.dart';

const driverEligibilityMessage = 'Complete driver verification and membership activation before submitting bids.';

bool driverCanBid(Map<String, dynamic> data, {DateTime? now}) {
  if ((data.containsKey('registrationStatus') && data['registrationStatus'] != 'approved') || data['accountType'] != 'driver' || data['identityVerificationStatus'] != 'verified' ||
      data['paymentStatus'] != 'verified' || data['membershipStatus'] != 'active' || data['accountStatus'] != 'active') {
    return false;
  }
  if (data['membershipPlan'] == 'founding_lifetime') {
    return true;
  }
  final until = DriverAdministration.date(data['membershipValidUntil']);
  return data['membershipPlan'] == 'standard_annual' && until != null && until.isAfter(now ?? DateTime.now());
}

class DriverRecord {
  DriverRecord(this.id, Map<String, dynamic> data) : data = Map.unmodifiable(data);
  final String id;
  final Map<String, dynamic> data;
  String text(String key, [String fallback = 'Not available']) => DriverAdministration.text(data[key], fallback);
}

class DriverAdministration {
  DriverAdministration({required Map<String, dynamic> profile, this.identity,
    List<DriverRecord> payments = const [], List<DriverRecord> history = const [], List<DriverRecord> operations = const []})
    : profile = Map.unmodifiable(profile), payments = List.unmodifiable(payments),
      history = List.unmodifiable(history), operations = List.unmodifiable(operations);
  final Map<String, dynamic> profile;
  final DriverRecord? identity;
  final List<DriverRecord> payments, history, operations;
  bool get isDriver => profile['accountType'] == 'driver';
  int get revision => profile['driverAdminRevision'] is int ? profile['driverAdminRevision'] as int : 0;
  String get identityStatus => text(profile['identityVerificationStatus'], 'pending');
  String get paymentStatus => text(profile['paymentStatus'], 'pending');
  String get membershipStatus => text(profile['membershipStatus'], 'pending');
  String get accountStatus => text(profile['accountStatus'], profile['status'] == 'active' ? 'active' : 'inactive');
  bool get canActivate => (!profile.containsKey('registrationStatus') || profile['registrationStatus'] == 'approved') && identityStatus == 'verified' && paymentStatus == 'verified' && profile['driverRegistrationNumber'] == null;
  static String text(Object? value, [String fallback = 'Not available']) =>
    value is String && value.trim().isNotEmpty ? value : fallback;
  static DateTime? date(Object? value) => value is Timestamp ? value.toDate().toUtc() : value is DateTime ? value.toUtc() : null;
  static String display(Object? value) {
    if (value == null) {
      return 'Not available';
    }
    final dateValue = date(value);
    if (dateValue != null) {
      return dateValue.toLocal().toString();
    }
    if (value is bool) {
      return value ? 'Yes' : 'No';
    }
    return value is String || value is num ? '$value' : 'Not available';
  }
}
