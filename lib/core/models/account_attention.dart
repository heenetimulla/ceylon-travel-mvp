import 'driver_administration.dart';

/// Current state comes only from users/{uid}, never a submitted snapshot.
String accountStatusLabel(Map<String, dynamic> user) {
  switch (user['registrationStatus']) {
    case 'draft': return 'DRAFT';
    case 'pending_review': return 'PENDING APPROVAL';
    case 'correction_required': return 'CORRECTION REQUIRED';
    case 'rejected': return 'REJECTED';
    case 'approved':
      if (user['accountStatus'] == 'suspended') { return 'SUSPENDED'; }
      if (user['accountStatus'] == 'inactive') { return 'INACTIVE'; }
      if (user['accountType'] == 'driver') {
        return driverCanBid(user) ? 'ACTIVE' : 'AWAITING PAYMENT / MEMBERSHIP';
      }
      return user['accountStatus'] == 'active' ? 'ACTIVE' : 'PENDING APPROVAL';
    default:
      final status = user['accountStatus'] ?? user['status'];
      return status is String ? status.toUpperCase() : 'UNKNOWN STATUS';
  }
}

enum RegistrationQueueFilter {
  all('All'), tourist('Tourists'), driver('Drivers'), correction('Correction Required'), payment('Payment & Activation');
  const RegistrationQueueFilter(this.label);
  final String label;
}
