import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/bid.dart';
import '../models/trip_post.dart';

class BidService {
  BidService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<List<Bid>> watchCreatorBids(TripPost tripPost) async* {
    try {
      final uid = await _requireReadProfile(tripPost);
      final parent = await _firestore
          .collection('trip_posts')
          .doc(tripPost.id)
          .get(const GetOptions(source: Source.server));
      if (!parent.exists) {
        throw const BidServiceException('This trip could not be found.');
      }
      _requireSameSession(uid);
      if (parent.data()?['creatorId'] != uid) {
        throw const BidServiceException(
          'You can only view bids for your own trips.',
        );
      }
      // Rules independently verify ownership of the stored parent trip.
      final query = _firestore
          .collection('trip_posts')
          .doc(tripPost.id)
          .collection('bids');
      await for (final snapshot in query.snapshots()) {
        _requireSameSession(uid);
        final bids = snapshot.docs.map((doc) => Bid.fromFirestore(doc)).toList()
          ..sort((a, b) {
            final aDate = a.createdAt;
            final bDate = b.createdAt;
            // Unresolved server timestamps sort last; IDs break all ties.
            if (aDate == null && bDate != null) return 1;
            if (aDate != null && bDate == null) return -1;
            final order = aDate == null || bDate == null
                ? 0
                : aDate.compareTo(bDate);
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
        yield bids;
      }
    } catch (error) {
      throw _readException(error);
    }
  }

  Stream<TripPost> watchCreatorTrip(TripPost tripPost) async* {
    try {
      final uid = await _requireReadProfile(tripPost);
      final ref = _firestore.collection('trip_posts').doc(tripPost.id);
      await for (final snapshot in ref.snapshots()) {
        _requireSameSession(uid);
        if (!snapshot.exists) {
          throw const BidServiceException('This trip could not be found.');
        }
        final trip = TripPost.fromFirestore(snapshot);
        if (trip.creatorId != uid) {
          throw const BidServiceException(
            'You can only view bids for your own trips.',
          );
        }
        yield trip;
      }
    } catch (error) {
      throw _readException(error);
    }
  }

  Future<void> acceptBid({
    required TripPost tripPost,
    required String bidId,
  }) async {
    try {
      final uid = await _requireReadProfile(tripPost);
      if (bidId.isEmpty || bidId.contains('/')) {
        throw const BidServiceException('This bid could not be found.');
      }
      final tripRef = _firestore.collection('trip_posts').doc(tripPost.id);
      final bidRef = tripRef.collection('bids').doc(bidId);
      await _firestore.runTransaction<void>((transaction) async {
        _requireSameSession(uid);
        final profile = await transaction.get(
          _firestore.collection('users').doc(uid),
        );
        final tripSnapshot = await transaction.get(tripRef);
        final bidSnapshot = await transaction.get(bidRef);
        final profileData = profile.data();
        if (profileData == null ||
            profileData['status'] != 'active' ||
            !['tourist', 'driver'].contains(profileData['accountType'])) {
          throw const BidServiceException(
            'Your account must be active to accept a bid.',
          );
        }
        final trip = tripSnapshot.data();
        if (trip == null) {
          throw const BidServiceException('This trip could not be found.');
        }
        if (trip['creatorId'] != uid) {
          throw const BidServiceException(
            'You can only accept bids for your own trips.',
          );
        }
        if (trip['status'] == 'accepted' ||
            trip['acceptedBidId'] != null ||
            trip['acceptedDriverId'] != null) {
          throw const BidServiceException(
            'This trip already has an accepted bid.',
          );
        }
        if (trip['status'] != 'open') {
          throw const BidServiceException(
            'This trip is no longer open for bidding.',
          );
        }
        final scheduledAt = trip['scheduledAt'];
        if (scheduledAt is! Timestamp ||
            !scheduledAt.toDate().isAfter(DateTime.now())) {
          throw const BidServiceException(
            'This trip is no longer scheduled in the future.',
          );
        }
        final bid = bidSnapshot.data();
        if (bid == null) {
          throw const BidServiceException('This bid could not be found.');
        }
        final driverId = bid['driverId'];
        if (bid['tripId'] != tripPost.id ||
            bid['status'] != 'submitted' ||
            driverId is! String ||
            driverId.trim().isEmpty ||
            driverId != bidId ||
            driverId == uid) {
          throw const BidServiceException(
            'This bid is no longer available for acceptance.',
          );
        }
        _requireSameSession(uid);
        transaction.update(tripRef, {
          'status': 'accepted',
          'acceptedBidId': bidId,
          'acceptedDriverId': driverId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(bidRef, {
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on BidServiceException {
      rethrow;
    } on FirebaseException catch (error) {
      switch (error.code) {
        case 'permission-denied':
          throw const BidServiceException(
            'You cannot accept this bid. Refresh the trip and try again.',
          );
        case 'unauthenticated':
          throw const BidServiceException(
            'Please sign in again to accept a bid.',
          );
        case 'unavailable':
        case 'network-request-failed':
        case 'deadline-exceeded':
          throw const BidServiceException(
            'Check your internet connection and try again.',
          );
        case 'aborted':
          throw const BidServiceException(
            'The trip changed while accepting. Refresh the trip and try again.',
          );
        default:
          throw const BidServiceException(
            'Could not accept this bid. Please try again.',
          );
      }
    } catch (_) {
      throw const BidServiceException(
        'Could not accept this bid. Please try again.',
      );
    }
  }

  // The strict driverId read rule denies missing documents on the server.
  // Such failures are surfaced as friendly errors, not treated as absent bids.
  Stream<Bid?> watchDriverBid(TripPost tripPost) async* {
    try {
      final uid = await _requireReadProfile(tripPost, accountType: 'driver');
      // Never query the collection for a driver, even with a client filter.
      final ref = _firestore
          .collection('trip_posts')
          .doc(tripPost.id)
          .collection('bids')
          .doc(uid);
      await for (final snapshot in ref.snapshots()) {
        _requireSameSession(uid);
        yield snapshot.exists ? Bid.fromFirestore(snapshot) : null;
      }
    } catch (error) {
      throw _readException(error);
    }
  }

  Future<String> _requireReadProfile(
    TripPost tripPost, {
    String? accountType,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const BidServiceException('Please sign in to view bids.');
    }
    if (tripPost.id.isEmpty || tripPost.id.contains('/')) {
      throw const BidServiceException('This trip could not be found.');
    }
    final profile = await _firestore
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server));
    final data = profile.data();
    if (!profile.exists || data == null) {
      throw const BidServiceException(
        'Your profile could not be found. Please sign in again.',
      );
    }
    if (data['status'] != 'active') {
      throw const BidServiceException(
        'Your account must be active to view bids.',
      );
    }
    if (!['tourist', 'driver'].contains(data['accountType']) ||
        (accountType != null && data['accountType'] != accountType)) {
      throw BidServiceException(
        accountType == 'driver'
            ? 'Only driver accounts can view their own driver bid.'
            : 'Your account cannot manage bids.',
      );
    }
    _requireSameSession(user.uid);
    return user.uid;
  }

  void _requireSameSession(String uid) {
    if (_auth.currentUser?.uid != uid) {
      throw const BidServiceException(
        'Your session changed. Please sign in again.',
      );
    }
  }

  BidServiceException _readException(Object error) {
    if (error is BidServiceException) return error;
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return const BidServiceException(
            'You do not have permission to view these bids.',
          );
        case 'unauthenticated':
          return const BidServiceException(
            'Please sign in again to view bids.',
          );
        case 'unavailable':
        case 'network-request-failed':
        case 'deadline-exceeded':
          return const BidServiceException(
            'Check your internet connection and try again.',
          );
      }
    }
    return const BidServiceException('Could not load bids. Please try again.');
  }

  static const vehicleTypes = [
    'TukTuk',
    'Small Car',
    'Sedan Car',
    'Van - Highroof',
    'Van - Flatroof',
    'SUV',
    'Bus',
  ];

  Future<void> submitBid({
    required TripPost tripPost,
    required int priceAmount,
    required String vehicleType,
    required String vehicleDetails,
    required String vehicleNumber,
    required int estimatedTripMinutes,
    required String message,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw const BidServiceException('Please sign in to submit a bid.');
      }
      if (priceAmount < 1 || priceAmount > 10000000) {
        throw const BidServiceException(
          'Enter a price from LKR 1 to LKR 10,000,000.',
        );
      }
      if (!vehicleTypes.contains(vehicleType)) {
        throw const BidServiceException('Select the vehicle you are offering.');
      }
      if (vehicleDetails.trim().isEmpty || vehicleDetails.trim().length > 160) {
        throw const BidServiceException(
          'Enter vehicle details up to 160 characters.',
        );
      }
      if (vehicleNumber.trim().isEmpty || vehicleNumber.trim().length > 40) {
        throw const BidServiceException(
          'Enter a vehicle number up to 40 characters.',
        );
      }
      if (estimatedTripMinutes < 1 || estimatedTripMinutes > 10080) {
        throw const BidServiceException(
          'Enter a trip duration from 1 minute to 7 days.',
        );
      }
      if (message.trim().length > 500) {
        throw const BidServiceException(
          'Keep your message within 500 characters.',
        );
      }
      if (tripPost.id.isEmpty || tripPost.id.contains('/')) {
        throw const BidServiceException('This trip could not be found.');
      }
      final profile = await _firestore
          .collection('users')
          .doc(user.uid)
          .get(const GetOptions(source: Source.server));
      final data = profile.data();
      if (!profile.exists || data == null) {
        throw const BidServiceException(
          'Your profile could not be found. Please sign in again.',
        );
      }
      if (data['status'] != 'active' || data['accountType'] != 'driver') {
        throw const BidServiceException(
          'Only active driver accounts can submit bids.',
        );
      }
      final name = data['fullName'];
      final rating = data['averageRating'];
      final completed = data['completedTripsCount'];
      final cancellation = data['cancellationRate'];
      if (name is! String ||
          name.trim().isEmpty ||
          rating is! num ||
          !rating.isFinite ||
          completed is! int ||
          cancellation is! num ||
          !cancellation.isFinite) {
        throw const BidServiceException(
          'Your driver profile is incomplete. Please check your profile.',
        );
      }
      final tripRef = _firestore.collection('trip_posts').doc(tripPost.id);
      final trip = await tripRef.get(const GetOptions(source: Source.server));
      final tripData = trip.data();
      if (!trip.exists || tripData == null) {
        throw const BidServiceException('This trip could not be found.');
      }
      if (tripData['status'] != 'open') {
        throw const BidServiceException(
          'This trip is no longer open for bids.',
        );
      }
      if (tripData['creatorId'] == user.uid) {
        throw const BidServiceException(
          'You cannot bid on your own trip post.',
        );
      }
      final scheduledAt = tripData['scheduledAt'];
      if (scheduledAt is! Timestamp ||
          !scheduledAt.toDate().isAfter(DateTime.now())) {
        throw const BidServiceException(
          'This trip is no longer scheduled in the future.',
        );
      }
      if (_auth.currentUser?.uid != user.uid) {
        throw const BidServiceException(
          'Your session changed. Please sign in again.',
        );
      }
      final bid = Bid(
        id: user.uid,
        tripId: tripPost.id,
        driverId: user.uid,
        driverName: name,
        driverRating: rating.toDouble(),
        completedTrips: completed,
        cancellationRate: cancellation.toDouble(),
        priceAmount: priceAmount,
        vehicleType: vehicleType,
        vehicleDetails: vehicleDetails.trim(),
        vehicleNumber: vehicleNumber.trim(),
        estimatedTripMinutes: estimatedTripMinutes,
        message: message.trim(),
        status: 'submitted',
      );
      // The fixed ID and create-only rules
      // atomically reject a second write, including concurrent submissions.
      await tripRef.collection('bids').doc(user.uid).set({
        ...bid.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on BidServiceException {
      rethrow;
    } on FirebaseException catch (error) {
      switch (error.code) {
        case 'already-exists':
          throw const BidServiceException(
            'You have already submitted a bid for this trip.',
          );
        case 'permission-denied':
          throw const BidServiceException(
            'Could not submit this bid. You may have already submitted a bid for this trip, or the trip is no longer available.',
          );
        case 'unavailable':
        case 'network-request-failed':
          throw const BidServiceException(
            'Check your internet connection and try again.',
          );
        case 'unauthenticated':
          throw const BidServiceException(
            'Please sign in again to submit a bid.',
          );
        default:
          throw const BidServiceException(
            'Could not submit your bid. Please try again.',
          );
      }
    } catch (_) {
      throw const BidServiceException(
        'Could not submit your bid. Please try again.',
      );
    }
  }
}

class BidServiceException implements Exception {
  const BidServiceException(this.message);
  final String message;
  @override
  String toString() => message;
}
