import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/active_trip_order.dart';
import 'package:taxi_app/core/models/public_profile.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/models/user_reputation.dart';
import 'package:taxi_app/core/widgets/participant_profile_card.dart';
import 'package:taxi_app/core/widgets/profile_avatar.dart';
import 'package:taxi_app/core/widgets/user_identity_header.dart';
import 'package:taxi_app/screens/driver/driver_home_screen.dart';
import 'package:taxi_app/screens/tourist/tourist_home_screen.dart';
import 'accepted_driver_trips_widget_test.dart' show acceptedTrip;

void main() {
  TripPost trip(String id, String status, int day) => TripPost.fromMap(id, acceptedTrip().toFirestore()
    ..['status'] = status ..['createdAt'] = Timestamp.fromDate(DateTime.utc(2026, 9, day)));

  test('Open first, newest within each group; history excluded without mutating input', () {
    final input = [trip('active-old', 'accepted', 2), trip('done', 'completed', 11),
      trip('open-old', 'open', 1), trip('cancelled', 'cancelled', 11),
      trip('active-new', 'end_requested', 10), trip('open-new', 'open', 3),
      trip('starting', 'start_requested', 5), trip('running', 'in_progress', 6)];
    expect(orderedActiveTrips(input).map((t) => t.id),
      ['open-new', 'open-old', 'active-new', 'running', 'starting', 'active-old']);
    expect(input.first.id, 'active-old');
    expect(input.length, 8);
  });
  test('Public model omits private fields and selects actual opposite participant', () {
    final safe = PublicProfile.fromMap({'uid': 'driver-1', 'fullName': 'Driver Name',
      'phoneNumber': 'private', 'email': 'private', 'nic': 'private', 'verification': {'selfie': 'private'}});
    expect(safe.toMap().keys, unorderedEquals(['uid', 'fullName', 'profilePhotoPath', 'verificationStatus',
      'completedTripsCount', 'cancellationCount', 'cancellationRate', 'averageRating', 'ratingsCount']));
    for (final status in TripPost.assignedStatuses) {
      final post = trip('t', status, 1);
      expect(PublicProfile.otherParticipant(post, 'creator-1'), 'driver-1');
      expect(PublicProfile.otherParticipant(post, 'driver-1'), 'creator-1');
      expect(PublicProfile.otherParticipant(post, 'stranger'), isNull);
    }
    expect(PublicProfile.otherParticipant(trip('t', 'open', 1), 'creator-1'), isNull);
    final partnerTrip = TripPost.fromMap('partner-trip', trip('t', 'accepted', 1).toFirestore()
      ..['driverId'] = 'creator-1');
    expect(PublicProfile.otherParticipant(partnerTrip, 'creator-1'), 'driver-1');
    expect(PublicProfile.otherParticipant(partnerTrip, 'driver-1'), 'creator-1');
  });
  for (final creator in [true, false]) {
    testWidgets('Participant profile and written review: creator=$creator', (tester) async {
      final uid = creator ? 'driver-1' : 'creator-1';
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ParticipantProfileCard(
        trip: trip('t', 'completed', 1), actor: creator ? 'creator-1' : 'driver-1',
        profileStream: Stream.value(PublicProfile(uid: uid, fullName: 'Other Participant',
          profilePhotoPath: 'unresolved/storage/path', verificationStatus: 'verified',
          reputation: const UserReputation(completedTripsCount: 48, cancellationCount: 2,
            cancellationRate: 4, averageRating: 4.8, ratingsCount: 31))),
        reviewsStream: Stream.value([{'stars': 5, 'comment': 'A reliable travel partner.',
          'createdAt': Timestamp.fromDate(DateTime(2026, 9, 11)), 'tripReference': 'CT-260911-ABC234'}]),
      )))));
      await tester.pumpAndSettle();
      expect(find.text(creator ? 'Accepted driver profile' : 'Hire creator profile'), findsOneWidget);
      expect(find.text('Other Participant'), findsOneWidget);
      expect(find.text('OP'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('${creator ? 'Completed trips' : 'Completed hires'}: 48'), findsOneWidget);
      expect(find.text('Cancellations: 2'), findsOneWidget);
      expect(find.text('Cancellation rate: 4%'), findsOneWidget);
      expect(find.text('Rating: 4.8 (31 reviews)'), findsOneWidget);
      await tester.ensureVisible(find.text('View Reviews'));
      await tester.tap(find.text('View Reviews'));
      await tester.pumpAndSettle();
      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('A reliable travel partner.'), findsOneWidget);
      expect(find.text('Trip: CT-260911-ABC234'), findsOneWidget);
      final context = tester.element(find.byType(ParticipantReviewsScreen));
      expect(find.text(MaterialLocalizations.of(context).formatMediumDate(DateTime(2026, 9, 11))), findsOneWidget);
    });
  }
  testWidgets('Unavailable cancellation metrics and no reviews are not fabricated', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ParticipantProfileCard(
      trip: trip('t', 'accepted', 1), actor: 'creator-1',
      profileStream: Stream.value(const PublicProfile(uid: 'driver-1', fullName: '', reputation: UserReputation())),
    ))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(find.text('Not Verified'), findsOneWidget);
    expect(find.text('Cancellations: Not available'), findsOneWidget);
    expect(find.text('Cancellation rate: Not available'), findsOneWidget);
    expect(find.text('View Reviews'), findsNothing);
  });
  for (final driver in [false, true]) {
    testWidgets('Dashboard reuses signed-in identity: driver=$driver', (tester) async {
      Future<Map<String, dynamic>?> profile() async => {'fullName': 'Signed In User', 'profilePhotoPath': 'unresolved/storage/photo'};
      await tester.pumpWidget(MaterialApp(home: driver
        ? DriverHomeScreen(postsStream: Stream.value([]), loadProfile: profile)
        : TouristHomeScreen(postsStream: Stream.value([]), loadProfile: profile)));
      await tester.pumpAndSettle();
      expect(find.byType(UserIdentityHeader), findsOneWidget);
      expect(find.byType(ProfileAvatar), findsOneWidget);
      expect(find.text('Signed In User'), findsOneWidget);
      expect(find.text('SU'), findsOneWidget);
    });
  }
}
