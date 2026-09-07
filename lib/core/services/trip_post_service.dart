import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/trip_post.dart';

class TripPostService {
  TripPostService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<List<TripPost>> watchTouristPosts() => _watchPosts('tourist');

  Stream<List<TripPost>> watchDriverPosts() => _watchPosts('driver');

  Stream<List<TripPost>> _watchPosts(String accountType) async* {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw const TripPostServiceException('Please sign in to view trip posts.');
      }
      final profile = await _firestore.collection('users').doc(user.uid).get(
        const GetOptions(source: Source.server),
      );
      final data = profile.data();
      if (!profile.exists || data == null) {
        throw const TripPostServiceException(
          'Your profile could not be found. Please sign in again.',
        );
      }
      if (data['status'] != 'active' || data['accountType'] != accountType) {
        throw const TripPostServiceException(
          'Your account cannot view this trip list. Please sign in again.',
        );
      }
      final isDriver = accountType == 'driver';
      // Single-field queries match the read rules without composite indexes.
      final query = isDriver
          ? _firestore.collection('trip_posts').where('status', isEqualTo: 'open')
          : _firestore.collection('trip_posts').where('touristId', isEqualTo: user.uid);
      await for (final snapshot in query.snapshots()) {
        if (_auth.currentUser?.uid != user.uid) {
          throw const TripPostServiceException(
            'Your session changed. Please sign in again.',
          );
        }
        final now = DateTime.now();
        final posts = snapshot.docs
            .map((doc) => TripPost.fromFirestore(doc))
            .where((post) =>
                post.status == 'open' &&
                !post.scheduledAt.isBefore(now) &&
                (!isDriver || post.creatorId != user.uid))
            .toList()
          ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
        yield posts;
      }
    } on TripPostServiceException {
      rethrow;
    } on FirebaseException catch (error) {
      if (error.code == 'unavailable' || error.code == 'network-request-failed') {
        throw const TripPostServiceException(
          'Check your internet connection and try again.',
        );
      }
      throw const TripPostServiceException(
        'Could not load trip posts. Please try again.',
      );
    } catch (_) {
      throw const TripPostServiceException(
        'Could not load trip posts. Please try again.',
      );
    }
  }

  Future<String> createTripPost({
    required String pickupLocationText,
    required String dropLocationText,
    required DateTime scheduledAt,
    required int adultsCount,
    required int kidsCount,
    required int baggageCount,
    required String vehiclePreference,
    required String notes,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw const TripPostServiceException(
          'Please sign in to create a post.',
        );
      }
      if (pickupLocationText.trim().isEmpty ||
          dropLocationText.trim().isEmpty) {
        throw const TripPostServiceException(
          'Enter pickup and drop locations.',
        );
      }
      if (adultsCount < 1 || kidsCount < 0 || baggageCount < 0) {
        throw const TripPostServiceException(
          'Check the passenger and baggage counts.',
        );
      }
      if (![
        'Any',
        'TukTuk',
        'Small Car',
        'Sedan Car',
        'Van - Highroof',
        'Van - Flatroof',
        'SUV',
        'Bus',
      ].contains(vehiclePreference)) {
        throw const TripPostServiceException(
          'Select a valid vehicle preference.',
        );
      }
      final profile = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      final data = profile.data();
      if (!profile.exists || data == null) {
        throw const TripPostServiceException(
          'Your profile could not be found. Please sign in again.',
        );
      }
      if (data['status'] != 'active') {
        throw const TripPostServiceException(
          'Your account must be active to create a post.',
        );
      }
      final creatorType = data['accountType'];
      if (creatorType != 'tourist' && creatorType != 'driver') {
        throw const TripPostServiceException(
          'Your account type cannot create trip posts.',
        );
      }
      final fullName = data['fullName'];
      if (fullName is! String || fullName.trim().isEmpty) {
        throw const TripPostServiceException(
          'Your profile is missing a name. Please complete your profile.',
        );
      }
      if (_auth.currentUser?.uid != user.uid) {
        throw const TripPostServiceException(
          'Your session changed. Please sign in again.',
        );
      }
      if (scheduledAt.isBefore(DateTime.now())) {
        throw const TripPostServiceException(
          'Choose a date and time in the future.',
        );
      }
      final ref = _firestore.collection('trip_posts').doc();
      final isTourist = creatorType == 'tourist';
      final post = TripPost(
        id: ref.id,
        creatorId: user.uid,
        creatorType: creatorType as String,
        creatorName: fullName.trim(),
        postType: 'trip_request',
        postOrigin: isTourist ? 'direct' : 'partner',
        touristId: isTourist ? user.uid : null,
        driverId: isTourist ? null : user.uid,
        pickupLocationText: pickupLocationText.trim(),
        dropLocationText: dropLocationText.trim(),
        scheduledAt: scheduledAt,
        adultsCount: adultsCount,
        kidsCount: kidsCount,
        baggageCount: baggageCount,
        vehiclePreference: vehiclePreference,
        notes: notes.trim(),
        status: 'open',
      );
      await ref.set({
        ...post.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return ref.id;
    } on TripPostServiceException {
      rethrow;
    } on FirebaseException catch (error) {
      switch (error.code) {
        case 'permission-denied':
          throw const TripPostServiceException(
            'You do not have permission to create this post.',
          );
        case 'unauthenticated':
          throw const TripPostServiceException(
            'Please sign in again to create a post.',
          );
        case 'unavailable':
        case 'network-request-failed':
          throw const TripPostServiceException(
            'Check your internet connection and try again.',
          );
        default:
          throw const TripPostServiceException(
            'Could not save your post. Please try again.',
          );
      }
    } catch (_) {
      throw const TripPostServiceException(
        'Could not save your post. Please try again.',
      );
    }
  }
}

class TripPostServiceException implements Exception {
  const TripPostServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
