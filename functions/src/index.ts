import {initializeApp} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import {getFunctions} from "firebase-admin/functions";
import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {defineString} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {executeDeadline, pendingDeadline, Phase, tripIdFromPayload} from "./lifecycle";
import {syncPublicProfile, syncPublicReview} from "./public_profiles";

initializeApp();
const db = getFirestore();
const region = defineString("LIFECYCLE_REGION", {default: "asia-southeast1"});
const serviceAccount = defineString("LIFECYCLE_SERVICE_ACCOUNT", {
  default: "trip-lifecycle@ceylon-travel-mvp.iam.gserviceaccount.com",
});
// Explicit Gen 2 URIs avoid assuming a Cloud Run URL from a function name.
// Empty defaults allow the private workers to be deployed before the scheduler.
const startUri = defineString("AUTO_START_TASK_URI", {default: ""});
const endUri = defineString("AUTO_COMPLETE_TASK_URI", {default: ""});

// These projections are independent of lifecycle scheduling and transactions.
export const publishUserProfile = onDocumentWritten({
  document: "users/{uid}", region, serviceAccount, retry: true,
}, (event) => syncPublicProfile(db, event.params.uid));
export const publishUserReputation = onDocumentWritten({
  document: "user_reputation/{uid}", region, serviceAccount, retry: true,
}, (event) => syncPublicProfile(db, event.params.uid));
export const publishWrittenReview = onDocumentWritten({
  document: "trip_posts/{tripId}/ratings/{direction}", region, serviceAccount, retry: true,
}, (event) => syncPublicReview(db, event.params.tripId, event.params.direction));

const taskOptions = {
  region, serviceAccount, invoker: "private" as const,
  timeoutSeconds: 60, maxInstances: 5,
  retryConfig: {maxAttempts: 100, maxRetrySeconds: 86400, minBackoffSeconds: 15, maxBackoffSeconds: 300, maxDoublings: 5},
  rateLimits: {maxConcurrentDispatches: 10, maxDispatchesPerSecond: 10},
};
async function dispatch(data: unknown, phase: Phase): Promise<void> {
  const tripId = tripIdFromPayload(data);
  try {
    const outcome = await executeDeadline(db, tripId, phase);
    logger.info("Lifecycle task finished", {tripId, phase, outcome});
  } catch (error) {
    logger.error("Lifecycle task failed; queue retry required", {tripId, phase, error});
    throw error;
  }
}
export const autoStartTrip = onTaskDispatched(taskOptions, (request) => dispatch(request.data, "start"));
export const autoCompleteTrip = onTaskDispatched(taskOptions, (request) => dispatch(request.data, "end"));

export const scheduleTripLifecycle = onDocumentWritten({
  document: "trip_posts/{tripId}", region, serviceAccount, retry: true,
}, async (event) => {
  if (!event.data?.after.exists) return;
  // Delivery is at least once and may be out of order. Never schedule from stale payload state.
  const tripId = event.params.tripId;
  const snapshot = await db.collection("trip_posts").doc(tripId).get();
  if (!snapshot.exists) return;
  const trip = snapshot.data()!;
  const phase = trip.status === "start_requested" ? "start" : trip.status === "end_requested" ? "end" : null;
  if (!phase) return;
  try {
    const deadline = pendingDeadline(trip, phase)!;
    const uri = phase === "start" ? startUri.value() : endUri.value();
    if (!/^https:\/\/[^/]+\.run\.app\/?$/.test(uri)) throw new Error("Configure the deployed private worker serviceConfig.uri");
    const name = phase === "start" ? "autoStartTrip" : "autoCompleteTrip";
    await getFunctions().taskQueue(`locations/${region.value()}/functions/${name}`).enqueue({tripId}, {
      scheduleTime: deadline.toDate(), dispatchDeadlineSeconds: 120, uri,
    });
    logger.info("Lifecycle task scheduled", {tripId, phase, deadline: deadline.toDate().toISOString()});
  } catch (error) {
    // No enqueue marker is written before success. Retry also covers commit/enqueue outages.
    // Duplicate tasks are safe: the worker transaction is the durable idempotency barrier.
    logger.error("Lifecycle enqueue failed", {tripId, phase, error});
    throw error;
  }
});
