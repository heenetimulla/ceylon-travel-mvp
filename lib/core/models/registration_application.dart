import 'driver_administration.dart';

const registrationAgreementVersion = '1.1';
const registrationOperatorName = 'VerTech Solutions';
const registrationAccessMessage = 'Your application must be approved before using trips or chat. Check your application status or contact support.';
const registrationResubmissionMessage = 'Your updated application will go through manual verification again. This may take additional time.';
// Preserve the exact historic v1.0 text for immutable acceptance records.
const registrationGuidelinesV1 = [
  'Provide complete and accurate information and all required documents.',
  'Submission does not mean approval. Applications are manually reviewed.',
  'Your NIC must be unique. A driver’s Driving Licence must also be unique.',
  'Duplicate or incorrect identity information may result in rejection.',
  'You may correct permitted information and resubmit when a correction is requested or an application is rejected.',
  'Every resubmitted application requires manual verification again. This takes time and may delay approval.',
  'Carefully check your information and documents before submitting.',
  'Submitting confirms that your information is accurate and that you accept manual verification.',
];

const registrationGuidelines = [
  ...registrationGuidelinesV1,
  'Ceylon Travel, operated by $registrationOperatorName (the planned operator name, not yet formally registered), is a non-commission marketplace and coordination platform.',
  'Ceylon Travel / $registrationOperatorName does not operate vehicles or directly provide transportation. Users and drivers/partners arrange and perform trips at their own risk.',
  'Each party must verify the other party, vehicle, trip details, payment arrangements, legality and suitability before proceeding.',
  'Ceylon Travel / $registrationOperatorName is not responsible for losses, disputes, accidents, injuries, misconduct, cancellations, incorrect information, payment disputes or misuse of trip information, except to the extent liability cannot legally be excluded.',
  'Do not misuse trip details, contact details, location information or personal information obtained through the app.',
  'Ceylon Travel / $registrationOperatorName will not intentionally sell private user information or improperly disclose it. Information may be used or disclosed where needed to operate the service, with permission, or where legally required.',
  'Reasonable security measures are used, but absolute digital security cannot be guaranteed.',
  'Using the platform means accepting responsibility for your own use of the service.',
];

const driverUpgradeVehicleTypes = ['Any', 'TukTuk', 'Small Car', 'Sedan Car',
  'Van - Highroof', 'Van - Flatroof', 'SUV', 'Bus'];

bool eligibleForDriverUpgrade(Map<String, dynamic> profile) =>
  profile['accountType'] == 'tourist' && applicationOperational(profile);

bool applicationOperational(Map<String, dynamic> profile) {
  if (profile['status'] != 'active' || !['tourist', 'driver'].contains(profile['accountType'])) { return false; }
  if ((profile['accountStatus'] ?? profile['status']) != 'active') { return false; }
  // Legacy profiles may lack registrationStatus, but driver eligibility is mandatory.
  if (profile.containsKey('registrationStatus') && profile['registrationStatus'] != 'approved') { return false; }
  return profile['accountType'] != 'driver' || driverCanBid(profile);
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
  required Map<String, String> evidence, required bool agreement, bool reuseNic = false}) {
  if (!reuseNic && (nic.trim().isEmpty || nic.trim().length > 40)) { return 'Enter your NIC number (up to 40 characters).'; }
  if (driver && (licence.trim().isEmpty || licence.trim().length > 40)) { return 'Enter your Driving Licence number (up to 40 characters).'; }
  if (!requiredApplicationEvidence(driver).where((type) => !reuseNic || type != 'nic')
    .every((type) => evidence[type]?.isNotEmpty == true)) { return 'Upload all required identity documents and your selfie.'; }
  if (!agreement) { return 'Read and accept the Registration Guidelines & Agreement.'; }
  return null;
}
