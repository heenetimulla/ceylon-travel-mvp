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

    final Finder viewDetailsButton = find.text('View Details').first;
    await tester.scrollUntilVisible(viewDetailsButton, 250);
    await tester.tap(viewDetailsButton);
    await tester.pumpAndSettle();

    expect(find.text('Trip Details'), findsOneWidget);
    expect(find.text('View Bids'), findsOneWidget);
    expect(find.text('Bandaranaike Airport'), findsWidgets);
  });
}
