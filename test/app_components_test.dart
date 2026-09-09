import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/app/app_theme.dart';
import 'package:taxi_app/core/widgets/app_components.dart';
import 'package:taxi_app/core/widgets/bid_card.dart';
import 'accepted_driver_trips_widget_test.dart' show acceptedBid;

void main() {
  testWidgets(
    'Route and statuses remain readable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
              child: const SingleChildScrollView(
                child: AppInfoCard(
                  children: [
                    AppRoute(
                      pickup: 'Bandaranaike International Airport arrivals',
                      destination: 'A hotel near Ella railway station',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppStatusChip('open'),
                        AppStatusChip('accepted'),
                        AppStatusChip('cancelled'),
                        AppStatusChip('closed'),
                        AppStatusChip('submitted'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Pickup'), findsOneWidget);
      expect(find.text('Destination'), findsOneWidget);
      for (final status in [
        'OPEN',
        'ACCEPTED',
        'CANCELLED',
        'CLOSED',
        'SUBMITTED',
      ]) {
        expect(find.text(status), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Offer action retains effective status and saving guards', (
    tester,
  ) async {
    var accepts = 0;
    Future<void> showOffer({
      String status = 'submitted',
      bool saving = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: BidCard(
                bid: acceptedBid.copyWith(status: 'submitted'),
                effectiveStatus: status,
                isSaving: saving,
                onAccept: () => accepts++,
              ),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byType(FilledButton));
    }

    await showOffer();
    expect(find.text('Vehicle number: WP CAB-1234'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    expect(accepts, 1);
    await showOffer(status: 'cancelled');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await showOffer(saving: true);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(accepts, 1);
  });
}
