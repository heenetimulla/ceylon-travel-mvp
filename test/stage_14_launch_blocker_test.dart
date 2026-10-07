import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/bid.dart';
import 'package:taxi_app/core/models/registration_application.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/services/trip_lifecycle_service.dart';
import 'package:taxi_app/core/widgets/trip_lifecycle_panel.dart';
import 'package:taxi_app/screens/driver/driver_home_screen.dart';
import 'package:taxi_app/screens/tourist/tourist_home_screen.dart';
import 'package:taxi_app/screens/tourist/tourist_bid_list_screen.dart';
import 'package:taxi_app/screens/trip/lifecycle_trip_screen.dart';
import 'accepted_driver_trips_widget_test.dart' show acceptedTrip, acceptedBid;

TripPost _unassigned(String status) => TripPost.fromMap('trip-1', acceptedTrip().toFirestore()
  ..['status'] = status
  ..['acceptedBidId'] = null
  ..['acceptedDriverId'] = null);

void main() {
  test('legacy compatibility never grants operational driver access on account type alone', () {
    final driver = <String, dynamic>{'status': 'active', 'accountStatus': 'active', 'accountType': 'driver'};
    expect(applicationOperational(driver), isFalse);
    driver.addAll({'identityVerificationStatus': 'verified', 'paymentStatus': 'verified',
      'membershipStatus': 'active', 'membershipPlan': 'founding_lifetime'});
    expect(applicationOperational(driver), isTrue);
    for (final entry in {'identityVerificationStatus': 'pending', 'paymentStatus': 'pending',
      'membershipStatus': 'pending', 'accountStatus': 'suspended', 'status': 'inactive'}.entries) {
      expect(applicationOperational({...driver, entry.key: entry.value}), isFalse);
    }
    expect(applicationOperational({...driver, 'membershipPlan': 'standard_annual',
      'membershipValidUntil': DateTime.utc(2000)}), isFalse);
    expect(applicationOperational({'status': 'active', 'accountType': 'tourist'}), isTrue);
  });

  for (final driver in [false, true]) {
    testWidgets('dashboard keeps one subscription through scrolling and post-route return: driver=$driver', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var listens = 0, cancels = 0;
      final feed = StreamController<List<TripPost>>(onListen: () { listens++; }, onCancel: () { cancels++; });
      addTearDown(feed.close);
      Future<Map<String, dynamic>?> profile() async => {'fullName': 'Launch User'};
      await tester.pumpWidget(MaterialApp(home: driver
        ? DriverHomeScreen(postsStream: feed.stream, loadProfile: profile)
        : TouristHomeScreen(postsStream: feed.stream, loadProfile: profile)));
      feed.add([]);
      await tester.pumpAndSettle();
      expect(listens, 1);
      final empty = find.text(driver ? 'No trips available' : 'Your next journey starts here');
      await tester.scrollUntilVisible(empty, 250);
      await tester.pumpAndSettle();
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(empty, 250);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(listens, 1);
      expect(cancels, 0);
      tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
      await tester.pumpAndSettle();
      final create = find.text(driver ? 'Create Hire Post' : 'Create Trip');
      await tester.scrollUntilVisible(create, 150);
      await tester.tap(create);
      await tester.pumpAndSettle();
      feed.add([_unassigned('open')]);
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Colombo Airport'), 250);
      expect(find.text('Colombo Airport'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(listens, 1);
      expect(cancels, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(cancels, 1);
    });
  }

  testWidgets('creator bids remain subscribed when the trip view errors then recovers', (tester) async {
    final trips = StreamController<TripPost>();
    var listens = 0, cancels = 0;
    final bids = StreamController<List<Bid>>(onListen: () { listens++; }, onCancel: () { cancels++; });
    addTearDown(trips.close);
    addTearDown(bids.close);
    final trip = _unassigned('open');
    await tester.pumpWidget(MaterialApp(home: TouristBidListScreen(
      tripPost: trip, tripStream: trips.stream, bidsStream: bids.stream)));
    trips.add(trip);
    bids.add([acceptedBid.copyWith(status: 'submitted')]);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Driver One'), 250);
    expect(listens, 1);
    trips.addError(StateError('Access unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load this trip.'), findsOneWidget);
    expect(cancels, 0);
    trips.add(trip);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Driver One'), 250);
    expect(find.text('Driver One'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(listens, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(cancels, 1);
  });

  testWidgets('lifecycle clears previously visible trip details after access loss', (tester) async {
    final trips = StreamController<TripPost>();
    addTearDown(trips.close);
    await tester.pumpWidget(MaterialApp(home: LifecycleTripScreen(
      tripId: 'trip-1', service: _Lifecycle(trips.stream))));
    trips.add(_unassigned('cancelled'));
    await tester.pump();
    expect(find.byType(TripLifecyclePanel), findsOneWidget);
    trips.addError(StateError('Permission denied'));
    await tester.pump();
    expect(find.byType(TripLifecyclePanel), findsNothing);
    expect(find.textContaining('This trip is unavailable.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signed-out lifecycle entry shows a recoverable error instead of throwing', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LifecycleTripScreen(
      tripId: 'trip-1', service: _Lifecycle(const Stream<TripPost>.empty(), signedOut: true))));
    await tester.pump();
    expect(find.textContaining('This trip is unavailable.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Lifecycle implements TripLifecycleService {
  _Lifecycle(this.trips, {this.signedOut = false});
  final Stream<TripPost> trips;
  final bool signedOut;
  @override
  String get uid => signedOut ? throw StateError('Please sign in.') : 'creator-1';
  @override
  Stream<TripPost> watchTrip(String id) => trips;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
