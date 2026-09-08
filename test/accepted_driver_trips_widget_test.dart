import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/bid.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/services/trip_post_service.dart';
import 'package:taxi_app/screens/driver/accepted_driver_trip_screen.dart';
import 'package:taxi_app/screens/driver/accepted_driver_trips_screen.dart';

TripPost acceptedTrip() => TripPost(
  id: 'trip-1',
  creatorId: 'creator-1',
  creatorType: 'tourist',
  creatorName: 'Trip Creator',
  postType: 'trip_request',
  postOrigin: 'direct',
  touristId: 'creator-1',
  pickupLocationText: 'Colombo Airport',
  dropLocationText: 'Ella Hotel',
  scheduledAt: DateTime(2030, 6, 15, 9),
  adultsCount: 2,
  kidsCount: 1,
  baggageCount: 3,
  vehiclePreference: 'Any',
  notes: 'Please use the main entrance.',
  status: 'accepted',
  acceptedBidId: 'driver-1',
  acceptedDriverId: 'driver-1',
);

const acceptedBid = Bid(
  id: 'driver-1',
  tripId: 'trip-1',
  driverId: 'driver-1',
  driverName: 'Driver One',
  driverRating: 4.5,
  completedTrips: 12,
  cancellationRate: 0,
  priceAmount: 18500,
  vehicleType: 'Small Car',
  vehicleDetails: 'Suzuki Wagon R Stingray 2017, White',
  vehicleNumber: 'WP CAB-1234',
  estimatedTripMinutes: 330,
  message: '',
  status: 'accepted',
);

void main() {
  testWidgets(
    'Accepted trip list moves from loading to empty to live trip cards',
    (tester) async {
      final controller = StreamController<List<TripPost>>();
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          home: AcceptedDriverTripsScreen(watchTrips: () => controller.stream),
        ),
      );
      expect(find.text('Loading your accepted trips...'), findsOneWidget);
      controller.add([]);
      await tester.pump();
      expect(find.textContaining('No accepted trips yet.'), findsOneWidget);
      final trip = acceptedTrip();
      controller.add([trip]);
      await tester.pumpAndSettle();
      expect(find.text('Colombo Airport -> Ella Hotel'), findsOneWidget);
      expect(find.text(trip.dateTime), findsOneWidget);
      expect(find.text('2 adults, 1 kid'), findsOneWidget);
      expect(find.text('3 bags'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Submit Bid'), findsNothing);
      controller.add([]);
      await tester.pumpAndSettle();
      expect(find.textContaining('No accepted trips yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'Accepted trip list retries a friendly error with a new subscription',
    (tester) async {
      var subscriptions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AcceptedDriverTripsScreen(
            watchTrips: () {
              subscriptions++;
              if (subscriptions == 1) {
                return Stream<List<TripPost>>.error(
                  const TripPostServiceException(
                    'Check your internet connection and try again.',
                  ),
                );
              }
              return Stream.value([acceptedTrip()]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Check your internet connection and try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(subscriptions, 2);
      expect(find.text('Colombo Airport -> Ella Hotel'), findsOneWidget);
    },
  );

  testWidgets(
    'Accepted destination displays real trip and own bid without trip actions',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final trip = acceptedTrip();
      await tester.pumpWidget(
        MaterialApp(
          home: AcceptedDriverTripScreen(
            tripPost: trip,
            watchBid: (requestedTrip) {
              expect(requestedTrip.id, trip.id);
              return Stream.value(acceptedBid);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('accepted'), findsOneWidget);
      expect(find.text('Colombo Airport'), findsOneWidget);
      expect(find.text('Ella Hotel'), findsOneWidget);
      expect(find.text(trip.dateTime), findsOneWidget);
      expect(find.text('Please use the main entrance.'), findsOneWidget);
      expect(find.text('Price: LKR 18,500'), findsOneWidget);
      expect(find.text('Vehicle type: Small Car'), findsOneWidget);
      expect(
        find.text('Vehicle: Suzuki Wagon R Stingray 2017, White'),
        findsOneWidget,
      );
      expect(find.text('Vehicle number: WP CAB-1234'), findsOneWidget);
      expect(
        find.text('Estimated trip duration: 5 hours 30 minutes'),
        findsOneWidget,
      );
      expect(find.text('Submit Bid'), findsNothing);
      expect(find.text('View Bids'), findsNothing);
      expect(find.text('Accept Bid'), findsNothing);
    },
  );
}
