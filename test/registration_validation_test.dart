import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/validation/registration_validation.dart';

void main() {
  test('Phone is mandatory and rejects whitespace', () {
    for (final value in ['', '   ', '\t\n']) {
      expect(validateRegistrationPhone(value), 'Phone number is required.');
    }
  });

  test('Phone accepts local and international formats with trimmed edges', () {
    for (final value in [
      '0771234567',
      '+94771234567',
      ' +94 77 123 4567 ',
      '(077) 123-4567',
      '+1 (212) 555-1234',
    ]) {
      expect(validateRegistrationPhone(value), isNull, reason: value);
    }
  });

  test(
    'Phone rejects letters, misplaced plus, invalid digit counts and brackets',
    () {
      for (final value in [
        'abc',
        '123456',
        '+1234567890123456',
        '077ABC4567',
        '077+1234567',
        '++94771234567',
        '(0771234567',
        '077)1234567',
        '077\n1234567',
      ]) {
        expect(
          validateRegistrationPhone(value),
          'Enter a valid phone number.',
          reason: value,
        );
      }
    },
  );
}
