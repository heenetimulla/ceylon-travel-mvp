import 'driver_administration.dart';

const registrationAgreementVersion = '1.0';
const registrationAccessMessage = 'Your application must be approved before using trips or chat. Check your application status or contact support.';
const registrationResubmissionMessage = 'Your updated application will go through manual verification again. This may take additional time.';
const registrationGuidelines = [
  'Provide complete and accurate information and all required documents.',
  'Submission does not mean approval. Applications are manually reviewed.',
  'Your NIC must be unique. A driver’s Driving Licence must also be unique.',
  'Duplicate or incorrect identity information may result in rejection.',
  'You may correct permitted information and resubmit when a correction is requested or an application is rejected.',
  'Every resubmitted application requires manual verification again. This takes time and may delay approval.',
  'Carefully check your information and documents before submitting.',
  'Submitting confirms that your information is accurate and that you accept manual verification.',
];

bool applicationOperational(Map<String, dynamic> profile) {
  if (profile['status'] != 'active' || !['tourist', 'driver'].contains(profile['accountType'])) { return false; }
  if ((profile['accountStatus'] ?? profile['status']) != 'active') { return false; }
  // New profile creation requires draft; only pre-rollout profiles lack this field.
  if (!profile.containsKey('registrationStatus')) { return true; }
  return profile['registrationStatus'] == 'approved' &&
    (profile['accountType'] != 'driver' || driverCanBid(profile));
}

String driverActivationMessage(Map<String, dynamic> profile) {
  if (profile['identityVerificationStatus'] != 'verified') {
    return 'Your identity verification is awaiting review. Your driver account is not active yet.';
  }
  if (profile['paymentStatus'] != 'verified') {
    return 'Identity verification approved. Your driver account is not active yet. '
      'Complete the registration payment and wait for payment verification and membership activation before accessing the Driver Dashboard.';
  }
  if (profile['membershipStatus'] != 'active') {
    return 'Identity and payment verified. Waiting for membership activation by an administrator. '
      'Your driver account is not active yet.';
  }
  return 'Membership is active. Your account is awaiting activation or has been made inactive. Contact support for assistance.';
}

List<String> requiredApplicationEvidence(bool driver) => driver ? ['nic', 'driving_licence', 'selfie'] : ['nic', 'selfie'];

String? validateApplicationSubmission({required bool driver, required String nic, required String licence,
  required Map<String, String> evidence, required bool agreement}) {
  if (nic.trim().isEmpty || nic.trim().length > 40) { return 'Enter your NIC number (up to 40 characters).'; }
  if (driver && (licence.trim().isEmpty || licence.trim().length > 40)) { return 'Enter your Driving Licence number (up to 40 characters).'; }
  if (!requiredApplicationEvidence(driver).every((type) => evidence[type]?.isNotEmpty == true)) { return 'Upload all required identity documents and your selfie.'; }
  if (!agreement) { return 'Read and accept the Registration Guidelines & Agreement.'; }
  return null;
}
