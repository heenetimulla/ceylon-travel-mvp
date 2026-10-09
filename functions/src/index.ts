import {initializeApp} from "firebase-admin/app";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getFunctions} from "firebase-admin/functions";
import {getMessaging} from "firebase-admin/messaging";
import {getAuth} from "firebase-admin/auth";
import {deliverWorkflowPush, firestoreWorkflowPort, syncNotificationStaff, WorkflowEvent} from "./workflow_push";
import {deliverChatPush, firestoreChatPushPort} from "./chat_push";
import {bidCreatedEvent, deliverTripPush, firestoreTripPushPort, tripTransitionEvent} from "./trip_push";
import {onDocumentCreated, onDocumentCreatedWithAuthContext, onDocumentUpdated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {defineString} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {executeDeadline, pendingDeadline, Phase, tripIdFromPayload} from "./lifecycle";
import {syncPublicProfile, syncPublicReview} from "./public_profiles";
export {processDriverAdministration, processRegistrationApplication} from "./driver_administration_trigger";

export {processAccountDeletion} from "./account_deletion_trigger";

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

// Chat delivery is isolated from Stage 10 lifecycle writes and scheduling.
export const notifyTripChatMessage = onDocumentCreated({
  document: "trip_posts/{tripId}/messages/{messageId}", region, serviceAccount,
  retry: false, timeoutSeconds: 60, maxInstances: 10,
}, async event => {
  const {tripId, messageId} = event.params;
  const outcome = await deliverChatPush(firestoreChatPushPort(db, getMessaging(), tripId, messageId),
    tripId, messageId, event.data?.data());
  if (outcome === "failed") logger.warn("Trip chat push attempt failed");
});

export const notifyTripBidCreated = onDocumentCreated({
  document: "trip_posts/{tripId}/bids/{bidId}", region, serviceAccount,
  retry: false, timeoutSeconds: 60, maxInstances: 10,
}, async event => {
  const {tripId, bidId} = event.params;
  const commit = event.data?.createTime;
  if (!commit) return;
  const key = `bid:${bidId}:${commit.seconds}:${commit.nanoseconds}`;
  const outcome = await deliverTripPush(firestoreTripPushPort(db, getMessaging(), tripId, key), tripId,
    bidCreatedEvent(tripId, bidId, event.data?.data()));
  if (outcome === "failed") logger.warn("Trip bid push attempt failed");
});

export const notifyTripTransition = onDocumentUpdated({
  document: "trip_posts/{tripId}", region, serviceAccount,
  retry: false, timeoutSeconds: 60, maxInstances: 10,
}, async event => {
  const change = event.data;
  if (!change) return;
  const notification = tripTransitionEvent(change.before.data(), change.after.data());
  if (!notification) return;
  const commit = change.after.updateTime;
  if (!commit) return;
  const key = `transition:${notification.type}:${commit.seconds}:${commit.nanoseconds}`;
  const outcome = await deliverTripPush(
    firestoreTripPushPort(db, getMessaging(), event.params.tripId, key), event.params.tripId, notification);
  if (outcome === "failed") logger.warn("Trip transition push attempt failed");
});

// Candidate discovery is server managed and never grants authorization. Every
// delivery independently checks current Auth claims, including revocations.
export const syncNotificationStaffTokens = onDocumentWritten({
  document: "users/{uid}/fcm_tokens/{tokenId}", region, serviceAccount,
  retry: true, timeoutSeconds: 60, maxInstances: 10,
}, async event => { await syncNotificationStaff(db, getAuth(), event.params.uid); });

async function notifyWorkflow(event: WorkflowEvent, commit: Timestamp | undefined): Promise<void> {
  if (!commit) return;
  const outcome = await deliverWorkflowPush(firestoreWorkflowPort(db, getAuth(), getMessaging(), event,
    `${commit.seconds}:${commit.nanoseconds}`), event);
  if (outcome === "failed") logger.warn("Workflow push attempt failed");
}

export const notifySupportRequestCreated = onDocumentCreatedWithAuthContext({
  document: "support_requests/{requestId}", region, serviceAccount,
  retry: false, timeoutSeconds: 120, maxInstances: 10,
}, async event => {
  if (!event.data) return;
  await notifyWorkflow({source: "support_request", path: event.data.ref.path, data: event.data.data(),
    id: event.params.requestId, authId: event.authType === "system" ? undefined : event.authId}, event.data.createTime);
});

export const notifySupportReplyCreated = onDocumentCreatedWithAuthContext({
  document: "support_requests/{requestId}/messages/{messageId}", region, serviceAccount,
  retry: false, timeoutSeconds: 120, maxInstances: 10,
}, async event => {
  if (!event.data) return;
  await notifyWorkflow({source: "support_message", path: event.data.ref.path, data: event.data.data(),
    uid: event.params.requestId, id: event.params.messageId,
    authId: event.authType === "system" ? undefined : event.authId}, event.data.createTime);
});

export const notifyRegistrationReviewEvent = onDocumentCreated({
  document: "registration_applications/{uid}/history/{operationId}", region, serviceAccount,
  retry: false, timeoutSeconds: 120, maxInstances: 10,
}, async event => {
  if (!event.data) return;
  await notifyWorkflow({source: "application", path: event.data.ref.path, data: event.data.data(),
    uid: event.params.uid, id: event.params.operationId}, event.data.createTime);
});

export const notifyDriverOperationCompleted = onDocumentUpdated({
  document: "users/{uid}/driver_operations/{operationId}", region, serviceAccount,
  retry: false, timeoutSeconds: 120, maxInstances: 10,
}, async event => {
  const change = event.data;
  if (!change || change.before.data().status !== "pending" || change.after.data().status !== "succeeded") return;
  await notifyWorkflow({source: "driver_operation", path: change.after.ref.path, data: change.after.data(),
    uid: event.params.uid, id: event.params.operationId}, change.after.updateTime);
});

export const notifyFoundingOfferClosed = onDocumentCreated({
  document: "admin_notifications/founding_offer_closed", region, serviceAccount,
  retry: false, timeoutSeconds: 120, maxInstances: 10,
}, async event => {
  if (!event.data) return;
  await notifyWorkflow({source: "founding", path: event.data.ref.path, data: event.data.data(),
    id: "founding_offer_closed"}, event.data.createTime);
});
