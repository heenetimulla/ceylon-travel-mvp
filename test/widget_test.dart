import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/main.dart';

void main() {
  testWidgets('Ceylon Travel app moves from splash to welcome screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const CeylonTravelApp());

    expect(find.text('Ceylon Travel'), findsOneWidget);
    expect(find.text('Sri Lanka travel & driver community'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(
      find.text('Replace travel WhatsApp groups with one smart app'),
      findsOneWidget,
    );
  });
}
