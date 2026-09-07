import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/app/ceylon_travel_app.dart';

Future<void> pumpToWelcome(WidgetTester tester) async {
  await tester.pumpWidget(const CeylonTravelApp());

  expect(find.text('Ceylon Travel'), findsOneWidget);

  await tester.pump(const Duration(seconds: 2));
  await tester.pump();

  expect(
    find.text('Replace travel WhatsApp groups with one smart app'),
    findsOneWidget,
  );
  expect(find.text('Login'), findsOneWidget);
  expect(find.text('Register'), findsOneWidget);
  expect(find.text('View Demo Flow'), findsOneWidget);
}

void main() {
  testWidgets('Ceylon Travel login validates required fields', (
    WidgetTester tester,
  ) async {
    await pumpToWelcome(tester);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Login to Ceylon Travel'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Email is required.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Email'), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Email is required.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'tourist@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Password is required.'), findsOneWidget);
    expect(find.text('Login to Ceylon Travel'), findsOneWidget);
    expect(find.text('How will you use Ceylon Travel?'), findsNothing);
    expect(find.text('Tourist Dashboard'), findsNothing);
    expect(find.text('Driver Dashboard'), findsNothing);
  });

  testWidgets('Ceylon Travel tourist registration validates required fields', (
    WidgetTester tester,
  ) async {
    await pumpToWelcome(tester);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Tourist/User'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Email optional'), findsNothing);

    final Finder createAccountButton = find.byKey(
      const Key('createAccountButton'),
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Full name is required.'), findsOneWidget);
    expect(find.text('Tourist Dashboard'), findsNothing);
  });

  testWidgets('Ceylon Travel driver registration validates driver fields', (
    WidgetTester tester,
  ) async {
    await pumpToWelcome(tester);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    final Finder driverAccountType = find.byKey(
      const Key('driverAccountTypeChip'),
    );
    await tester.ensureVisible(driverAccountType);
    await tester.tap(driverAccountType);
    await tester.pumpAndSettle();

    expect(find.text('Vehicle type'), findsOneWidget);
    expect(find.text('Vehicle number'), findsOneWidget);
    expect(find.text('Operating area'), findsOneWidget);
    expect(find.text('Available areas'), findsOneWidget);
    expect(find.text('NIC / ID upload placeholder'), findsOneWidget);
    expect(find.text('Selfie verification placeholder'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Full name'),
      'Test Driver',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number'),
      '+94771234567',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'driver@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'City / District'),
      'Colombo',
    );

    final Finder createAccountButton = find.byKey(
      const Key('createAccountButton'),
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Vehicle type is required.'), findsOneWidget);
    expect(find.text('Driver Dashboard'), findsNothing);
  });
}
