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
  testWidgets('Ceylon Travel login demo route works', (
    WidgetTester tester,
  ) async {
    await pumpToWelcome(tester);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('Login to Ceylon Travel'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(
      find.text('Firebase authentication will be connected in Week 3.'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('How will you use Ceylon Travel?'), findsOneWidget);
  });

  testWidgets('Ceylon Travel register and tourist trip flow works', (
    WidgetTester tester,
  ) async {
    await pumpToWelcome(tester);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Tourist/User'), findsOneWidget);
    expect(find.text('Driver'), findsOneWidget);

    final Finder createAccountButton = find.byKey(
      const Key('createAccountButton'),
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Tourist Dashboard'), findsWidgets);
    await tester.tap(find.text('Create Trip / Hire Post'));
    await tester.pumpAndSettle();

    expect(find.text('Create Trip / Hire Post'), findsWidgets);
    expect(find.text('Pickup location'), findsOneWidget);
    expect(find.text('Drop location'), findsOneWidget);
    expect(
      find.text(
        'Tourists can request trips and drivers can post hires they cannot complete. Drivers will see open posts and send private bids.',
      ),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    final Finder viewDetailsButton = find
        .widgetWithText(TextButton, 'View Details')
        .first;
    await tester.ensureVisible(viewDetailsButton);
    await tester.pumpAndSettle();
    await tester.tap(viewDetailsButton);
    await tester.pumpAndSettle();

    expect(find.text('Trip Details'), findsOneWidget);
    expect(find.text('View Bids'), findsOneWidget);
    expect(find.text('Bandaranaike Airport'), findsWidgets);
    expect(find.text('Posted by'), findsOneWidget);
    expect(find.text('Creator type'), findsOneWidget);

    final Finder viewBidsButton = find.widgetWithText(
      OutlinedButton,
      'View Bids',
    );
    await tester.ensureVisible(viewBidsButton);
    await tester.pumpAndSettle();
    await tester.tap(viewBidsButton);
    await tester.pumpAndSettle();

    expect(
      find.text('Bids are private. Only you can see driver prices.'),
      findsOneWidget,
    );

    final Finder firstAcceptBidButton = find
        .widgetWithText(FilledButton, 'Accept Bid')
        .first;
    await tester.ensureVisible(firstAcceptBidButton);
    await tester.pumpAndSettle();
    await tester.tap(firstAcceptBidButton);
    await tester.pumpAndSettle();

    expect(find.text('Accept this driver bid?'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Accept Bid'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ACCEPTED'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).last, const Offset(0, 500));
    await tester.pumpAndSettle();

    final Finder pendingTripButton = find.widgetWithText(
      FilledButton,
      'Go to Pending Trip',
    );
    await tester.ensureVisible(pendingTripButton);
    await tester.pumpAndSettle();
    await tester.tap(pendingTripButton);
    await tester.pumpAndSettle();

    expect(find.text('Pending Trip'), findsOneWidget);

    final Finder openChatButton = find.widgetWithText(
      FilledButton,
      'Open Chat',
    );
    await tester.scrollUntilVisible(openChatButton, 250);
    await tester.tap(openChatButton);
    await tester.pumpAndSettle();

    expect(find.text('Trip Chat'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Pending Trip'), findsOneWidget);

    final Finder confirmCompletedButton = find.widgetWithText(
      OutlinedButton,
      'Confirm Completed',
    );
    await tester.scrollUntilVisible(confirmCompletedButton, 250);
    await tester.tap(confirmCompletedButton);
    await tester.pumpAndSettle();

    final Finder openCompletedTripsButton = find.widgetWithText(
      FilledButton,
      'Open Completed Trips',
    );
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(openCompletedTripsButton);
    await tester.pumpAndSettle();
    await tester.tap(openCompletedTripsButton);
    await tester.pumpAndSettle();

    expect(find.text('Completed Trips'), findsOneWidget);

    final Finder rateTripButton = find
        .widgetWithText(FilledButton, 'Rate Trip')
        .first;
    await tester.ensureVisible(rateTripButton);
    await tester.tap(rateTripButton);
    await tester.pumpAndSettle();

    expect(find.text('Rate Trip'), findsOneWidget);
    expect(find.text('Trip summary'), findsOneWidget);
  });

  testWidgets('Ceylon Travel driver registration path works', (
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

    final Finder createAccountButton = find.byKey(
      const Key('createAccountButton'),
    );
    await tester.ensureVisible(createAccountButton);
    await tester.tap(createAccountButton);
    await tester.pumpAndSettle();

    expect(find.text('Driver Dashboard'), findsWidgets);
    expect(find.text('Create Hire Post'), findsOneWidget);
    expect(
      find.text('Got a hire you cannot do? Post it for other drivers.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Create Hire Post'));
    await tester.pumpAndSettle();

    expect(find.text('Create Trip / Hire Post'), findsWidgets);
  });
}
