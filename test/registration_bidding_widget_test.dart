import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/enums/account_type.dart';
import 'package:taxi_app/screens/auth/registration_screen.dart';

void main() {
  for (final type in [AccountType.tourist, AccountType.driver]) {
    testWidgets(
      '$type registration rejects an invalid phone before creating an account',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: RegistrationScreen(initialAccountType: type)),
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Full name'),
          'Test Person',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Phone number'),
          '   ',
        );
        final createButton = find.byKey(const Key('createAccountButton'));
        final registrationScrollable = find.byType(Scrollable).first;
        Future<void> tapCreateAccount() async {
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            createButton,
            300,
            scrollable: registrationScrollable,
          );
          await tester.pumpAndSettle();
          await tester.drag(registrationScrollable, const Offset(0, -120));
          await tester.pumpAndSettle();
          expect(createButton.hitTestable(), findsOneWidget);
          await tester.tap(createButton);
          await tester.pumpAndSettle();
        }

        await tapCreateAccount();
        expect(find.text('Phone number is required.'), findsOneWidget);
        // Dismiss the first validation message so it cannot cover the button
        // at the bottom of the form during the next submission.
        await tester.drag(find.byType(SnackBar), const Offset(0, 150));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Phone number'),
          'not a phone',
        );
        await tapCreateAccount();
        expect(find.text('Enter a valid phone number.'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'Driver primary vehicle dropdown has exactly seven options and supports selection',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: RegistrationScreen(initialAccountType: AccountType.driver),
        ),
      );
      final finder = find.byType(DropdownButtonFormField<String>);
      final dropdown = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: finder,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(dropdown.items!.map((item) => item.value).toList(), [
        'TukTuk',
        'Small Car',
        'Sedan Car',
        'Van - Highroof',
        'Van - Flatroof',
        'SUV',
        'Bus',
      ]);
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Small Car').last);
      await tester.pumpAndSettle();
      final state = tester.state<FormFieldState<String>>(finder);
      expect(state.value, 'Small Car');
      expect(find.text('Any'), findsNothing);
    },
  );
}
