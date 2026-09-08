import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/widgets/trip_cancellation_button.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/widgets/bid_card.dart';

import 'accepted_driver_trips_widget_test.dart' show acceptedTrip, acceptedBid;

void main() {
  for (final status in ['open', 'accepted']) {
    testWidgets('Creator $status warning gates form and Keep Trip changes nothing', (tester) async {
      final map = acceptedTrip().toFirestore()..['status'] = status;
      if (status == 'open') {
        map['acceptedBidId'] = null;
        map['acceptedDriverId'] = null;
        map['scheduledAt'] = DateTime.utc(2020);
      }
      var calls = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TripCancellationButton(trip: TripPost.fromMap('trip-1', map), byDriver: false,
          onCancel: (_, _) async { calls++; }),
      )));
      await tester.tap(find.text('Cancel Trip'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.byType(Form), findsNothing);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Keep Trip'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, 0);
      await tester.tap(find.text('Cancel Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I Understand - Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(Form), findsOneWidget);
      expect(calls, 0);
      if (status == 'open') {
        expect(find.text('No cancellation penalty will apply.'), findsOneWidget);
        expect(find.textContaining('within 2 hours'), findsNothing);
      }
      await tester.tap(find.text('Keep Trip'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });
  }

  testWidgets('Submitted bid under cancelled parent is historical and disabled', (tester) async {
    final trip = TripPost.fromMap('trip-1', acceptedTrip().toFirestore()
      ..['status'] = 'cancelled'..['acceptedBidId'] = null..['acceptedDriverId'] = null);
    final bid = acceptedBid.copyWith(status: 'submitted');
    final before = bid.toFirestore();
    var accepts = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      BidCard(bid: bid, effectiveStatus: bid.effectiveStatusFor(trip), onAccept: () => accepts++),
    ))));
    expect(find.text('TRIP CANCELLED'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(accepts, 0);
    expect(bid.toFirestore(), before);
    expect(bid.status, 'submitted');
  });

  testWidgets('Creator warning, mandatory Other details, trimmed save and duplicate protection', (tester) async {
    final saving = Completer<void>();
    var calls = 0;
    String? savedText;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      TripCancellationButton(trip: acceptedTrip(), byDriver: false,
        onCancel: (code, text) {
          calls++;
          expect(code, 'other');
          savedText = text;
          return saving.future;
        }),
    )));
    await tester.tap(find.text('Cancel Trip'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this trip?'), findsOneWidget);
    expect(find.textContaining('This trip will be permanently cancelled and will not reopen for bidding.'), findsOneWidget);
    expect(find.byType(Form), findsNothing);
    await tester.tap(find.text('I Understand - Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(Form), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Trip'));
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Trip'));
    await tester.pump();
    expect(find.text('Enter details for Other.'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField), '  Changed plans  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel Trip'));
    await tester.pump();
    expect(calls, 1);
    expect(savedText, 'Changed plans');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Keep Trip')).onPressed, isNull);
    saving.complete();
    await tester.pumpAndSettle();
    expect(find.text('Trip cancelled.'), findsOneWidget);
  });

  testWidgets('Driver sees reopen and exclusion warning and can keep trip', (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      TripCancellationButton(trip: acceptedTrip(), byDriver: true,
        onCancel: (_, _) async { calls++; }),
    )));
    await tester.tap(find.text('Cancel Trip'));
    await tester.pumpAndSettle();
    expect(find.text('Cancel this trip?'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('If you cancel this trip, it will reopen for other drivers.'), findsOneWidget);
    expect(find.textContaining('You will not be able to bid on this trip again.'), findsOneWidget);
    expect(find.byType(Form), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Keep Trip'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, 0);
  });

  for (final hoursAway in [3, 1]) {
    testWidgets('Driver warning shows penalty preview at $hoursAway hours and Continue opens form', (tester) async {
      final trip = TripPost.fromMap('trip-1', acceptedTrip().toFirestore()
        ..['scheduledAt'] = DateTime.now().add(Duration(hours: hoursAway)));
      var calls = 0;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        TripCancellationButton(trip: trip, byDriver: true,
          onCancel: (_, _) async { calls++; }),
      )));
      await tester.tap(find.text('Cancel Trip'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(Form), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      const noPenalty = 'No cancellation penalty will apply because the trip is more than 2 hours away.';
      const penalty = 'This cancellation is within 2 hours of the trip and will count toward your cancellation record.';
      expect(find.text(hoursAway >= 2 ? noPenalty : penalty), findsOneWidget);
      expect(find.text(hoursAway >= 2 ? penalty : noPenalty), findsNothing);
      expect(calls, 0);
      await tester.tap(find.text('I Understand - Continue'));
      await tester.pumpAndSettle();
      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.text('I Understand - Continue'), findsNothing);
      expect(calls, 0);
      await tester.tap(find.text('Keep Trip'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, 0);
    });
  }
}
