import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/app/ceylon_travel_app.dart';

void main() {
  testWidgets('Ceylon Travel login and account type flow works', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CeylonTravelApp());

    expect(find.text('Ceylon Travel'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(
      find.text('Replace travel WhatsApp groups with one smart app'),
      findsOneWidget,
    );

    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(find.text('Continue with phone'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('How will you use Ceylon Travel?'), findsOneWidget);

    await tester.tap(find.text('Tourist / Customer'));
    await tester.pumpAndSettle();

    expect(find.text('Create tourist/customer profile'), findsOneWidget);

    await tester.tap(find.text('Create User Account'));
    await tester.pumpAndSettle();

    expect(find.text('Tourist Dashboard'), findsWidgets);
    await tester.tap(find.text('Create Trip Post'));
    await tester.pumpAndSettle();

    expect(find.text('Trip advertisement'), findsOneWidget);
    expect(find.text('Pickup location'), findsOneWidget);
    expect(find.text('Drop location'), findsOneWidget);

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
}
