import 'package:cloud_firestore/cloud_firestore.dart';
import 'registration_application.dart';

/// Current account summary only. Application/evidence snapshots are not loaded.
class AccountProfile {
  AccountProfile(Map<String, dynamic> data, {required this.loginEmail})
    : _data = Map.unmodifiable(data);

  final Map<String, dynamic> _data;
  final String? loginEmail;
  String value(String key) {
    final value = _data[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : 'Not available';
  }
  String get fullName => value('fullName');
  String get city => _data['city'] is String ? _data['city'] as String : '';
  String get phoneNumber => value('phoneNumber');
  bool get isDriver => _data['accountType'] == 'driver';
  String? get driverUpgradeStatus => _data['driverUpgradeStatus'] is String ? _data['driverUpgradeStatus'] as String : null;
  bool get canRequestDriverUpgrade => eligibleForDriverUpgrade(_data) && !_data.containsKey('driverUpgradeStatus');
  String get accountType => isDriver ? 'Driver' : 'Tourist / User';
  String get registrationStatus => _data.containsKey('registrationStatus')
    ? value('registrationStatus') : 'Legacy account';
  String get accountStatus => _data.containsKey('accountStatus')
    ? value('accountStatus') : value('status');
  String get registrationNumber => _data['driverRegistrationNumber'] is num
    ? '${_data['driverRegistrationNumber']}' : 'Not assigned';
  String get membershipExpiry {
    if (_data['membershipPlan'] == 'founding_lifetime') {
      return 'Lifetime';
    }
    final raw = _data['membershipValidUntil'];
    final date = raw is Timestamp ? raw.toDate() : raw is DateTime ? raw : null;
    if (date == null) {
      return 'Not available';
    }
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
