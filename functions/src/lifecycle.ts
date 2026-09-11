import {DocumentData, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";

export type Phase = "start" | "end";
const settings = {
  start: {status: "start_requested", requested: "startRequestedAt", deadline: "startAutoStartAt", seconds: 180},
  end: {status: "end_requested", requested: "endRequestedAt", deadline: "endAutoCompleteAt", seconds: 1800},
} as const;

export function tripIdFromPayload(payload: unknown): string {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) throw new Error("Invalid task payload");
  const value = payload as Record<string, unknown>;
  if (Object.keys(value).length !== 1 || !validId(value.tripId)) throw new Error("Task requires only tripId");
  return value.tripId;
}
function validId(value: unknown): value is string {
  return typeof value === "string" && value.length > 0 && Buffer.byteLength(value) <= 1500 &&
    !value.includes("/") && value !== "." && value !== ".." && !/^__.*__$/.test(value);
}

/** Uses only stored Firestore timestamps; never a device or invocation clock. */
export function pendingDeadline(trip: DocumentData, phase: Phase): Timestamp | null {
  const config = settings[phase];
  if (trip.status !== config.status) return null;
  if (!validId(trip.creatorId) || !validId(trip.acceptedDriverId) ||
      !validId(trip.acceptedBidId) || trip.creatorId === trip.acceptedDriverId) {
    throw new Error("Pending trip has invalid performing-driver assignment");
  }
  const requested = trip[config.requested];
  const deadline = trip[config.deadline];
  if (!(requested instanceof Timestamp) || !(deadline instanceof Timestamp) ||
      deadline.seconds !== requested.seconds + config.seconds || deadline.nanoseconds !== requested.nanoseconds) {
    throw new Error("Pending trip has invalid authoritative deadline");
  }
  return deadline;
}

function count(value: unknown): number {
  if (value === undefined) return 0;
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0 || value >= Number.MAX_SAFE_INTEGER) {
    throw new Error("Invalid reputation count; trusted repair required");
  }
  return value;
}

/** Whitelist public fields; never copy private contact/profile data. */
function completedReputation(profile: DocumentData, publicData?: DocumentData): DocumentData {
  const completed = count(profile.completedTripsCount);
  const ratings = count(profile.ratingsCount);
  const stars = count(profile.ratingStarsTotal);
  const average = profile.averageRating ?? 0;
  if (typeof average !== "number" || !Number.isFinite(average) || average < 0 || average > 5) {
    throw new Error("Invalid rating aggregate; trusted repair required");
  }
  if (publicData && (count(publicData.completedTripsCount) !== completed ||
      count(publicData.ratingsCount) !== ratings || count(publicData.ratingStarsTotal) !== stars ||
      (publicData.averageRating ?? 0) !== average)) {
    throw new Error("Private/public reputation mismatch; trusted repair required");
  }
  return {
    completedTripsCount: completed + 1,
    ratingsCount: ratings, ratingStarsTotal: stars, averageRating: average,
    // Preserve the existing public cancellation policy; never fabricate a rate.
    cancellationCount: publicData?.cancellationCount ?? null,
    cancellationRate: publicData?.cancellationRate ?? null,
  };
}

export async function executeDeadline(db: Firestore, tripId: string, phase: Phase): Promise<"changed" | "noop"> {
  tripIdFromPayload({tripId});
  const ref = db.collection("trip_posts").doc(tripId);
  return db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    if (!snapshot.exists) return "noop";
    const trip = snapshot.data()!;
    const deadline = pendingDeadline(trip, phase);
    // Covers manual confirmation, duplicates, stale tasks, cancellation and deletion.
    if (!deadline) return "noop";
    // readTime is supplied by Firestore, including on transaction retries.
    const now = snapshot.readTime;
    if (now.seconds < deadline.seconds ||
        (now.seconds === deadline.seconds && now.nanoseconds < deadline.nanoseconds)) {
      // Do not acknowledge an early task and silently lose the future transition.
      throw new Error("Deadline not yet due; retry task");
    }
    const parties = [];
    if (phase === "end") {
      for (const uid of [trip.creatorId, trip.acceptedDriverId] as string[]) {
        const profileRef = db.collection("users").doc(uid);
        const reputationRef = db.collection("user_reputation").doc(uid);
        const profile = await tx.get(profileRef);
        const reputation = await tx.get(reputationRef);
        if (!profile.exists) throw new Error("Missing participant profile; trusted repair required");
        parties.push({profileRef, reputationRef, data: completedReputation(profile.data()!, reputation.data())});
      }
    }
    // Every read above precedes every write; status and counters share one commit.
    tx.update(ref, phase === "start" ? {
      status: "in_progress", startedAt: FieldValue.serverTimestamp(),
      startMethod: "auto_started", updatedAt: FieldValue.serverTimestamp(),
    } : {
      status: "completed", endedAt: FieldValue.serverTimestamp(),
      completionMethod: "auto_completed", updatedAt: FieldValue.serverTimestamp(),
    });
    for (const party of parties) {
      tx.update(party.profileRef, {
        completedTripsCount: party.data.completedTripsCount, lastCompletedTripId: tripId,
      });
      tx.set(party.reputationRef, party.data);
    }
    return "changed";
  });
}
