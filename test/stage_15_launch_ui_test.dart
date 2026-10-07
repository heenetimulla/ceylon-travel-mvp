import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/app/app_colors.dart';
import 'package:taxi_app/app/app_theme.dart';
import 'package:taxi_app/screens/auth/registration_screen.dart';
import 'package:taxi_app/screens/support/support_screens.dart';
import 'package:taxi_app/screens/trip/create_trip_post_screen.dart';

Widget launchForm(Widget screen, {double keyboard = 0}) => MaterialApp(
  theme: AppTheme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: const TextScaler.linear(1.6),
      viewInsets: EdgeInsets.only(bottom: keyboard),
    ),
    child: child!,
  ),
  home: screen,
);

void narrowPhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(target, 180,
    scrollable: find.byType(Scrollable).first, maxScrolls: 60);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Color? labelColor(WidgetTester tester, String label) => tester.widget<RichText>(
  find.descendant(of: find.text(label), matching: find.byType(RichText)),
).text.style?.color;

void main() {
  testWidgets('Account choices remain distinct and usable on a narrow phone', (tester) async {
    narrowPhone(tester);
    await tester.pumpWidget(launchForm(const RegistrationScreen()));
    final tourist = find.byKey(const Key('touristAccountTypeChip'));
    final driver = find.byKey(const Key('driverAccountTypeChip'));
    await reveal(tester, tourist);
    expect(tester.widget<ChoiceChip>(tourist).selected, isTrue);
    expect(labelColor(tester, 'Tourist/User'), AppColors.surface);
    expect(labelColor(tester, 'Driver/Partner'), AppColors.charcoal);
    await reveal(tester, driver);
    expect(tester.getSize(driver).height, greaterThanOrEqualTo(48));
    await tester.tap(driver);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(driver).selected, isTrue);
    expect(tester.widget<ChoiceChip>(tourist).selected, isFalse);
    expect(labelColor(tester, 'Driver/Partner'), AppColors.surface);
    expect(find.text('Vehicle number'), findsOneWidget);
    await reveal(tester, find.byKey(const Key('createAccountButton')));
  });

  testWidgets('Disabled selected option retains readable text', (tester) async {
    await tester.pumpWidget(launchForm(const Scaffold(body: ChoiceChip(
      label: Text('Driver/Partner'), selected: true, onSelected: null,
    ))));
    expect(labelColor(tester, 'Driver/Partner'), AppColors.charcoal);
  });

  testWidgets('Trip controls and validation remain reachable with the keyboard', (tester) async {
    narrowPhone(tester);
    await tester.pumpWidget(launchForm(const CreateTripPostScreen(), keyboard: 240));
    final date = find.ancestor(of: find.text('Select date'),
      matching: find.byWidgetPredicate((widget) => widget is OutlinedButton));
    final time = find.ancestor(of: find.text('Select time'),
      matching: find.byWidgetPredicate((widget) => widget is OutlinedButton));
    await reveal(tester, date);
    final dateRect = tester.getRect(date);
    await reveal(tester, time);
    expect(tester.getSize(time).width, dateRect.width);
    expect(tester.getSize(time).width, greaterThan(240));
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await reveal(tester, dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    final highroof = find.text('Van - Highroof').last;
    await tester.ensureVisible(highroof);
    await tester.tap(highroof);
    await tester.pumpAndSettle();
    expect(tester.state<FormFieldState<String>>(dropdown).value, 'Van - Highroof');
    expect(tester.takeException(), isNull);
    await reveal(tester, find.widgetWithText(TextField, 'Notes (optional)'));
    final submit = find.byWidgetPredicate((widget) => widget is FilledButton);
    await reveal(tester, submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Enter a pickup location.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Support explains its temporarily disabled submit action', (tester) async {
    narrowPhone(tester);
    final profile = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(launchForm(SupportFormScreen(loadProfile: () => profile.future)));
    final loading = find.widgetWithText(FilledButton, 'Loading contact details...');
    await reveal(tester, loading);
    expect(tester.widget<FilledButton>(loading).onPressed, isNull);
    profile.complete({'phoneNumber': '+94771234567'});
    await tester.pumpAndSettle();
    final submit = find.widgetWithText(FilledButton, 'Submit Request');
    await reveal(tester, submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });
}
