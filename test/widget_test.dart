import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taxi_app/app/ceylon_travel_app.dart';
import 'package:taxi_app/core/services/auth_preferences_service.dart';
import 'package:taxi_app/screens/auth/login_screen.dart';
import 'package:taxi_app/screens/welcome_screen.dart';

Future<void> pumpToWelcome(WidgetTester tester) async {
  await tester.pumpWidget(
    CeylonTravelApp(resolveSession: () async => const WelcomeScreen()),
  );

  expect(find.text('Ceylon Travel'), findsOneWidget);

  await tester.pump(const Duration(seconds: 2));
  await tester.pump();

  expect(find.text('Discover Sri Lanka, your way'), findsOneWidget);
  expect(find.text('Login'), findsOneWidget);
  expect(find.text('Register'), findsOneWidget);
  expect(find.text('View Demo Flow'), findsOneWidget);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Login restores only the last successful email', (tester) async {
    const preferences = AuthPreferencesService();
    await preferences.saveLastLoginEmail('  saved@example.com  ');

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    final emailField = find.widgetWithText(TextField, 'Email');
    final passwordField = find.widgetWithText(TextField, 'Password');
    expect(
      tester.widget<TextField>(emailField).controller!.text,
      'saved@example.com',
    );
    expect(tester.widget<TextField>(passwordField).controller!.text, isEmpty);

    await tester.enterText(emailField, 'another@example.com');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Login'));
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Password is required.'), findsOneWidget);
    expect(await preferences.getLastLoginEmail(), 'saved@example.com');
    final storage = await SharedPreferences.getInstance();
    expect(storage.getKeys(), {'auth.last_successful_login_email'});
  });

  testWidgets('Delayed email restoration preserves user edits', (tester) async {
    final preferences = _DelayedAuthPreferences();
    await tester.pumpWidget(
      MaterialApp(home: LoginScreen(authPreferences: preferences)),
    );
    final emailField = find.widgetWithText(TextField, 'Email');
    await tester.enterText(emailField, 'new@example.com');
    await tester.enterText(emailField, '');

    preferences.email.complete('saved@example.com');
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(emailField).controller!.text, isEmpty);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'Password'))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('Ceylon Travel login validates required fields', (
    WidgetTester tester,
  ) async {
    await pumpToWelcome(tester);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Login to Ceylon Travel'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Login'));
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('Email is required.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Email'), '   ');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Login'));
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();
    expect(find.text('Email is required.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'tourist@example.com',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Login'));
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
    expect(find.widgetWithText(ListTile, 'Identity document'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Photo verification'), findsOneWidget);

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

class _DelayedAuthPreferences extends AuthPreferencesService {
  final email = Completer<String?>();

  @override
  Future<String?> getLastLoginEmail() => email.future;
}
