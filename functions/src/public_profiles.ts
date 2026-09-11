import {DocumentData, Firestore} from "firebase-admin/firestore";

/** Explicit whitelist: no contact, verification evidence, or private account fields. */
export function publicProfile(uid: string, user: DocumentData, reputation?: DocumentData): DocumentData {
  const metrics = reputation ?? user;
  return {
    uid,
    fullName: typeof user.fullName === "string" ? user.fullName.trim() : "",
    profilePhotoPath: typeof user.profilePhotoPath === "string" ? user.profilePhotoPath : null,
    verificationStatus: user.verification?.status === "approved" || user.verification?.status === "verified"
      ? "verified" : "not_verified",
    completedTripsCount: metrics.completedTripsCount ?? 0,
    averageRating: metrics.averageRating ?? 0,
    ratingsCount: metrics.ratingsCount ?? 0,
    // Only the existing trusted public reputation supplies cancellation metrics.
    cancellationCount: reputation?.cancellationCount ?? null,
    cancellationRate: reputation?.cancellationRate ?? null,
  };
}

export async function syncPublicProfile(db: Firestore, uid: string): Promise<void> {
  await db.runTransaction(async (tx) => {
    const user = await tx.get(db.collection("users").doc(uid));
    const reputation = await tx.get(db.collection("user_reputation").doc(uid));
    const target = db.collection("user_public_profiles").doc(uid);
    if (!user.exists) { tx.delete(target); return; }
    tx.set(target, publicProfile(uid, user.data()!, reputation.data()));
  });
}

/** Read-only projection of the original rating, not a second rating system. */
export async function syncPublicReview(db: Firestore, tripId: string, direction: string): Promise<void> {
  if (!["creator_to_driver", "driver_to_creator"].includes(direction)) return;
  await db.runTransaction(async (tx) => {
    const tripRef = db.collection("trip_posts").doc(tripId);
    const tripDoc = await tx.get(tripRef);
    const ratingDoc = await tx.get(tripRef.collection("ratings").doc(direction));
    if (!tripDoc.exists || !ratingDoc.exists) return;
    const trip = tripDoc.data()!;
    const rating = ratingDoc.data()!;
    const targetUid = direction === "creator_to_driver" ? trip.acceptedDriverId : trip.creatorId;
    const authorUid = direction === "creator_to_driver" ? trip.creatorId : trip.acceptedDriverId;
    if (trip.status !== "completed" || typeof targetUid !== "string" || !targetUid ||
        targetUid === authorUid || rating.ratedUserUid !== targetUid || rating.ratedByUid !== authorUid ||
        !Number.isInteger(rating.stars) || rating.stars < 1 || rating.stars > 5 ||
        typeof rating.comment !== "string" || !rating.comment.trim() || rating.comment.length > 1000) {
      throw new Error("Invalid source rating; public review not published");
    }
    const target = db.collection("user_public_profiles").doc(targetUid).collection("reviews").doc(`${tripId}_${direction}`);
    tx.set(target, {
      stars: rating.stars, comment: rating.comment.trim(),
      createdAt: rating.createdAt ?? null, tripReference: trip.tripReference ?? null,
    });
  });
}
