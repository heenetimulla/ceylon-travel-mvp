import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/trip_post.dart';
import '../models/trip_cancellation.dart';

class TripCancellationService {
  TripCancellationService({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Future<void> cancelByAcceptedDriver({
    required String tripId,
    required String reasonCode,
    required String reasonText,
  }) => _cancel(tripId, reasonCode, reasonText, byDriver: true);

  Future<void> cancelByCreator({
    required String tripId,
    required String reasonCode,
    required String reasonText,
  }) => _cancel(tripId, reasonCode, reasonText, byDriver: false);

  Future<void> _cancel(
    String tripId,
    String code,
    String text, {
    required bool byDriver,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw const TripCancellationException('Please sign in again.');
    }
    if (tripId.isEmpty || tripId.contains('/')) {
      throw const TripCancellationException('This trip could not be found.');
    }
    final reasons = byDriver
        ? driverCancellationReasons
        : creatorCancellationReasons;
    final validation = validateCancellationReason(code, text, reasons);
    if (validation != null) throw TripCancellationException(validation);
    final details = text.trim();
    final tripRef = _firestore.collection('trip_posts').doc(tripId);

    // Try the no-penalty branch first. Rules compare the boolean with request.time.
    // Only a rejected, completely unwritten transaction is retried with true.
    // This handles clock skew and crossing the boundary without persisting an
    // inaccurate client-clock decision. Every retry repeats all authorization.
    for (final penalty in [false, true]) {
      try {
        await _firestore.runTransaction<void>((tx) async {
          final profile = (await tx.get(
            _firestore.collection('users').doc(uid),
          )).data();
          final snapshot = await tx.get(tripRef);
          if (_auth.currentUser?.uid != uid) {
            throw const TripCancellationException(
              'Your session changed. Please sign in again.',
            );
          }
          if (profile == null ||
              profile['status'] != 'active' ||
              !['tourist', 'driver'].contains(profile['accountType']) ||
              (byDriver && profile['accountType'] != 'driver')) {
            throw const TripCancellationException(
              'Your account cannot cancel this trip.',
            );
          }
          if (!snapshot.exists) {
            throw const TripCancellationException(
              'This trip could not be found.',
            );
          }
          final trip = TripPost.fromFirestore(snapshot);
          if (!byDriver && trip.status == 'open') {
            if (trip.creatorId != uid || trip.acceptedBidId != null ||
                trip.acceptedDriverId != null) {
              throw const TripCancellationException(
                'This unassigned trip is no longer available to cancel.',
              );
            }
            // The creator can never bid on their own post, so their UID cannot
            // collide with an accepted-bid history ID. Withdrawal is terminal.
            final historyRef = tripRef.collection('cancellations').doc(uid);
            final record = TripCancellation(
              id: historyRef.id,
              tripId: tripId,
              cancelledByUid: uid,
              cancelledByRole: 'creator',
              reasonCode: code,
              reasonText: details,
              penaltyApplied: false,
              previousStatus: 'open',
              resultingStatus: 'cancelled',
            );
            // Acceptance IDs are already null. Leave counts, exclusions and
            // every bid untouched, including legacy absent parent fields.
            tx.update(tripRef, {
              'status': 'cancelled',
              'lastCancellationBy': uid,
              'lastCancellationReason': details.isEmpty
                  ? reasons[code]!
                  : '${reasons[code]}: $details',
              'lastCancellationAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            tx.set(historyRef, {
              ...record.toFirestore(),
              'cancelledAt': FieldValue.serverTimestamp(),
            });
            return;
          }
          if (trip.status != 'accepted' ||
              trip.acceptedBidId == null ||
              trip.acceptedDriverId == null ||
              (byDriver
                  ? trip.acceptedDriverId != uid || trip.creatorId == uid
                  : trip.creatorId != uid)) {
            throw const TripCancellationException(
              'This accepted trip is no longer available to cancel. Refresh and try again.',
            );
          }
          final bidRef = tripRef.collection('bids').doc(trip.acceptedBidId!);
          final bid = (await tx.get(bidRef)).data();
          if (bid == null ||
              bid['status'] != 'accepted' ||
              bid['driverId'] != trip.acceptedDriverId ||
              bid['tripId'] != tripId ||
              trip.acceptedBidId != trip.acceptedDriverId) {
            throw const TripCancellationException(
              'The accepted bid changed. Refresh and try again.',
            );
          }
          if (_auth.currentUser?.uid != uid) {
            throw const TripCancellationException(
              'Your session changed. Please sign in again.',
            );
          }
          // A bid can be cancelled only once and never becomes submitted again.
          // Its fixed UID is therefore a unique, rules-addressable history ID.
          final historyRef = tripRef
              .collection('cancellations')
              .doc(trip.acceptedBidId!);
          final result = byDriver ? 'open' : 'cancelled';
          final record = TripCancellation(
            id: historyRef.id,
            tripId: tripId,
            cancelledByUid: uid,
            cancelledByRole: byDriver ? 'driver' : 'creator',
            reasonCode: code,
            reasonText: details,
            penaltyApplied: penalty,
            previousStatus: 'accepted',
            resultingStatus: result,
          );
          tx.update(tripRef, {
            'status': result,
            'acceptedBidId': null,
            'acceptedDriverId': null,
            'excludedDriverIds': byDriver
                ? {...trip.excludedDriverIds, uid}.toList()
                : trip.excludedDriverIds,
            'cancellationCount': trip.cancellationCount + 1,
            'lastCancellationBy': uid,
            'lastCancellationReason': details.isEmpty
                ? reasons[code]!
                : '${reasons[code]}: $details',
            'lastCancellationAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
          tx.update(bidRef, {
            'status': byDriver ? 'cancelled' : 'trip_cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          });
          tx.set(historyRef, {
            ...record.toFirestore(),
            'cancelledAt': FieldValue.serverTimestamp(),
          });
        });
        return;
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' && !penalty) continue;
        throw TripCancellationException(
          [
                'unavailable',
                'deadline-exceeded',
                'network-request-failed',
              ].contains(error.code)
              ? 'Check your internet connection and try again.'
              : 'Could not cancel this trip. Refresh the trip and try again.',
        );
      }
    }
  }
}

class TripCancellationException implements Exception {
  const TripCancellationException(this.message);
  final String message;
  @override
  String toString() => message;
}
