/// Friendly preflight only; the trusted operation worker validates every value.
String? validateDriverActionField(String key, String? value, String label, {bool reasonRequired = false}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) {
    if (key == 'reason' && !reasonRequired) { return null; }
    return switch (key) {
      'depositorName' => 'Depositor name is required.',
      'claimedAmountLkr' => 'Enter the payment amount.',
      'claimedPaymentDate' => 'Select the payment date.',
      'bankTransactionReference' => 'Bank transaction reference is required.',
      'reason' => 'Enter a reason for this decision.',
      _ => '$label is required.',
    };
  }
  if (key == 'claimedAmountLkr' && (int.tryParse(text) ?? 0) <= 0) {
    return 'Enter a positive payment amount in whole LKR.';
  }
  if (key == 'claimedPaymentDate') {
    final date = DateTime.tryParse(text);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) || date == null ||
        date.toIso8601String().substring(0, 10) != text) {
      return 'Enter a valid payment date (YYYY-MM-DD).';
    }
  }
  return null;
}
