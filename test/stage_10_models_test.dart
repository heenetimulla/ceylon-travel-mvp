import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/trip_post.dart';
import 'package:taxi_app/core/models/trip_lifecycle.dart';
import 'package:taxi_app/core/models/readable_reference.dart';
import 'package:taxi_app/core/models/rating.dart';
import 'package:taxi_app/core/models/user_reputation.dart';
import 'package:taxi_app/core/models/support_request.dart';
import 'accepted_driver_trips_widget_test.dart' show acceptedTrip;

void main() {
  final now = DateTime.utc(2030, 1, 1, 12);
  TripPost trip(String status, {int secondsUntilDue = 1}) => TripPost.fromMap('trip-1', acceptedTrip().toFirestore()
    ..['status'] = status
    ..['startAutoStartAt'] = Timestamp.fromDate(now.add(Duration(seconds: secondsUntilDue)))
    ..['endAutoCompleteAt'] = Timestamp.fromDate(now.add(Duration(seconds: secondsUntilDue))));
  test('Lifecycle exact participant and state permissions', () {
    for (final entry in [
      (LifecycleAction.requestStart, 'accepted', 'driver-1'),
      (LifecycleAction.confirmStart, 'start_requested', 'creator-1'),
      (LifecycleAction.requestEnd, 'in_progress', 'driver-1'),
      (LifecycleAction.confirmEnd, 'end_requested', 'creator-1'),
    ]) {
      expect(() => validateLifecycle(trip(entry.$2), entry.$3, entry.$1), returnsNormally);
      for (final outsider in ['stranger', entry.$3 == 'creator-1' ? 'driver-1' : 'creator-1']) {
        expect(() => validateLifecycle(trip(entry.$2), outsider, entry.$1), throwsStateError);
      }
      expect(() => validateLifecycle(trip('open'), entry.$3, entry.$1), throwsStateError);
    }
  });
  test('Manual preflight does not use device time to authorize deadlines', () {
    // Only Firestore rules can authorize the deadline boundary.
    expect(() => validateLifecycle(trip('start_requested', secondsUntilDue: 0), 'creator-1', LifecycleAction.confirmStart), returnsNormally);
    expect(() => validateLifecycle(trip('end_requested', secondsUntilDue: 0), 'creator-1', LifecycleAction.confirmEnd), returnsNormally);
  });
  test('Legacy lifecycle fields are null and Stage 9 cancelability remains narrow', () {
    final data = acceptedTrip().toFirestore();
    for (final key in ['tripReference', 'startRequestedAt', 'startAutoStartAt', 'startedAt', 'startMethod', 'endRequestedAt', 'endAutoCompleteAt', 'endedAt', 'completionMethod']) { data.remove(key); }
    final legacy = TripPost.fromMap('trip-1', data);
    expect(legacy.tripReference, isNull); expect(legacy.startedAt, isNull); expect(legacy.endedAt, isNull);
    expect(legacy.startAutoStartAt, isNull); expect(legacy.endAutoCompleteAt, isNull);
    for (final status in ['open', 'accepted']) { expect(trip(status).canCancel, isTrue); }
    for (final status in ['start_requested', 'in_progress', 'end_requested', 'completed', 'cancelled']) { expect(trip(status).canCancel, isFalse); }
  });
  test('Reference is readable, serialized, and independent of internal ID and status', () {
    final reference = generateReference('CT', now: DateTime.utc(2026,9,10), random: Random(7));
    expect(reference, matches(RegExp(r'^CT-260910-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}$')));
    final data = acceptedTrip().toFirestore()..['tripReference'] = reference;
    for (final state in TripPost.assignedStatuses) {
      data['status'] = state;
      final post = TripPost.fromMap('internal-id', data);
      expect(post.tripReference, reference); expect(post.toFirestore()['tripReference'], reference);
      expect(post.tripReference, isNot(post.id));
    }
  });
  test('Trip references use the Sri Lanka calendar date at midnight boundaries', () {
    for (final entry in [
      (DateTime.utc(2026, 9, 10, 18, 29, 59, 999, 999), '260910'),
      (DateTime.utc(2026, 9, 11, 6, 30), '260911'),
      (DateTime.utc(2026, 9, 10, 18, 30), '260911'),
      (DateTime.utc(2026, 9, 10, 23, 59), '260911'),
      (DateTime.utc(2026, 9, 30, 18, 30), '261001'),
      (DateTime.utc(2026, 12, 31, 18, 30), '270101'),
    ]) {
      final reference = generateReference('CT', now: entry.$1, random: Random(7));
      expect(reference, matches(RegExp('^CT-${entry.$2}-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{6}\$')));
    }
  });
  test('Support dates remain UTC and reference suffix generation is unchanged', () {
    final instant = DateTime.utc(2026, 9, 10, 18, 30);
    final tripReference = generateReference('CT', now: instant, random: Random(7));
    final supportReference = generateReference('SUP', now: instant, random: Random(7));
    expect(tripReference, startsWith('CT-260911-'));
    expect(supportReference, startsWith('SUP-260910-'));
    expect(tripReference.split('-').last, supportReference.split('-').last);
  });
  test('Mutual rating roles, no self-rating, stars and required review', () {
    expect(Rating.direction(trip('completed'), 'creator-1'), 'creator_to_driver');
    expect(Rating.direction(trip('completed'), 'driver-1'), 'driver_to_creator');
    expect(() => Rating.direction(trip('accepted'), 'creator-1'), throwsStateError);
    expect(() => Rating.direction(trip('completed'), 'stranger'), throwsStateError);
    final self = TripPost.fromMap('trip-1', trip('completed').toFirestore()..['acceptedDriverId'] = 'creator-1');
    expect(() => Rating.direction(self, 'creator-1'), throwsStateError);
    for (final stars in [0,6]) { expect(() => Rating.validate(stars,'Review'), throwsArgumentError); }
    for (final stars in [1,5]) { expect(() => Rating.validate(stars,'Review'), returnsNormally); }
    expect(() => Rating.validate(5, '  '), throwsArgumentError);
    expect(() => Rating.validate(5, 'a' * 1001), throwsArgumentError);
    final stats = const UserReputation().rated(5).rated(4);
    expect(stats.averageRating, 4.5); expect(stats.ratingsCount, 2); expect(stats.completedTripsCount, 0);
    expect(stats.completed().completedTripsCount, 1);
  });
  test('Support categories, acknowledgements and required contact number', () {
    expect(supportCategories.keys, containsAll(['complaint','feedback','suggestion','question','registration_help','app_usage_help','other']));
    expect(creatorComplaintCategories.keys, containsAll(['driver_no_show','driver_started_without_passenger','wrong_start_time','wrong_end_time','driver_ended_incorrectly','driver_behaviour','vehicle_issue','safety_concern','payment_price_issue','other']));
    expect(driverComplaintCategories.keys, containsAll(['passenger_no_show','creator_unreachable','incorrect_hire_details','wrong_pickup_drop','payment_incorrect','payment_incomplete','passenger_creator_behaviour','trip_changed_unexpectedly','other']));
    for (final phone in ['', 'hello', '123']) {
      expect(() => validateSupport(category:'question',contactNumber:phone,subject:'Help',message:'Please assist'), throwsArgumentError);
    }
    for (final category in supportCategories.keys) {
      expect(() => validateSupport(category:category,contactNumber:'+94771234567',subject:'Help',message:'Please assist'), returnsNormally);
      expect(supportAcknowledgement(category,'SUP-260910-ABC234'), isNotEmpty);
    }
    expect(supportAcknowledgement('complaint','SUP-260910-ABC234'), contains('SUP-260910-ABC234'));
    expect(generateReference('SUP'), startsWith('SUP-'));
  });
  test('Contact snapshot remains independent of a later profile phone change', () {
    final profile = {'phoneNumber': '+94771234567'};
    final request = SupportRequest(id:'r',supportReference:'SUP-260910-ABC234',userId:'u',userRole:'driver',userName:'Driver',contactNumber:'+94779876543',category:'complaint',subject:'Help',message:'Details',status:'open');
    profile['phoneNumber'] = '+94112345678';
    final restored = SupportRequest.fromMap(request.toFirestore());
    expect(restored.contactNumber, '+94779876543'); expect(restored.contactNumber, isNot(profile['phoneNumber']));
  });
}
