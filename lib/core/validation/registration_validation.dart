/// Registration contact validation only; this does not verify ownership by SMS.
String? validateRegistrationPhone(String value) {
  final phone = value.trim();
  if (phone.isEmpty) return 'Phone number is required.';
  // Local/international numbers: optional leading +, spaces, hyphens and
  // parentheses. Require 7-15 digits, with balanced, non-nested parentheses.
  if (phone.length > 40 ||
      !RegExp(r'^\+?[0-9(][0-9 ()-]*[0-9)]$').hasMatch(phone)) {
    return 'Enter a valid phone number.';
  }
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 7 || digits.length > 15) {
    return 'Enter a valid phone number.';
  }
  var depth = 0;
  for (final character in phone.split('')) {
    if (character == '(') depth++;
    if (character == ')') depth--;
    if (depth < 0 || depth > 1) return 'Enter a valid phone number.';
  }
  if (depth != 0 || phone.contains('()')) return 'Enter a valid phone number.';
  return null;
}
