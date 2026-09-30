import {createHash} from "node:crypto";
import {Firestore, Timestamp} from "firebase-admin/firestore";
import {Messaging} from "firebase-admin/messaging";
import {ChatPushPort, deliverPushRecipient, firestorePushPort, tripPushPayload} from "./chat_push";

type Data = Record<string, unknown>;
export const tripPushBodies = {
  new_bid: "You received a new bid for your trip.",
  bid_accepted: "Your bid was accepted.",
  trip_start_requested: "Your driver is ready to start the trip.",
  trip_started: "Your trip has started.",
  trip_end_requested: "Your driver requested to complete the trip.",
  trip_completed: "Your trip has been completed.",
  trip_cancelled: "The trip was cancelled by the trip creator.",
  trip_reopened: "The assigned driver cancelled. Your trip is open for bids again.",
} as const;
export type TripPushType = keyof typeof tripPushBodies;
export interface TripPushEvent {
  type: TripPushType;
  before?: Data;
  after: Data;
  bidId: string;
}
export interface TripPushPort extends ChatPushPort {
  loadBid(id: string): Promise<Data | undefined>;
  loadCancellation(id: string): Promise<Data | undefined>;
}
const id = (v: unknown): v is string => typeof v === "string" && v.length > 0 &&
  Buffer.byteLength(v) <= 1500 && !v.includes("/") && v !== "." && v !== "..";
const sameTime = (a: unknown, b: unknown): boolean =>
  a instanceof Timestamp && b instanceof Timestamp && a.isEqual(b);
const assigned = (t: Data): boolean => id(t.creatorId) && id(t.acceptedDriverId) &&
  id(t.acceptedBidId) && t.creatorId !== t.acceptedDriverId;

export function bidCreatedEvent(tripId: string, bidId: string, bid?: Data): TripPushEvent | null {
  if (!id(tripId) || !id(bidId) || !bid || bid.id !== bidId || bid.driverId !== bidId ||
      bid.tripId !== tripId || bid.status !== "submitted" || !(bid.createdAt instanceof Timestamp) ||
      typeof bid.priceAmount !== "number" || !Number.isSafeInteger(bid.priceAmount) || bid.priceAmount <= 0) return null;
  return {type: "new_bid", after: bid, bidId};
}

export function tripTransitionEvent(before?: Data, after?: Data): TripPushEvent | null {
  if (!before || !after || before.creatorId !== after.creatorId || !id(after.creatorId) ||
      !(after.updatedAt instanceof Timestamp)) return null;
  const transition = `${before.status}>${after.status}`;
  const types: Record<string, TripPushType> = {
    "open>accepted": "bid_accepted", "accepted>start_requested": "trip_start_requested",
    "start_requested>in_progress": "trip_started", "in_progress>end_requested": "trip_end_requested",
    "end_requested>completed": "trip_completed", "accepted>cancelled": "trip_cancelled",
    "accepted>open": "trip_reopened",
  };
  const type = types[transition];
  if (!type) return null;
  const cancellation = type === "trip_cancelled" || type === "trip_reopened";
  const assignment = cancellation ? before : after;
  if (!assigned(assignment)) return null;
  if (type !== "bid_accepted" && !cancellation &&
      (before.acceptedDriverId !== after.acceptedDriverId || before.acceptedBidId !== after.acceptedBidId)) return null;
  if (cancellation && (after.acceptedDriverId != null || after.acceptedBidId != null ||
      after.lastCancellationBy !== (type === "trip_cancelled" ? before.creatorId : before.acceptedDriverId))) return null;
  if (type === "trip_started" && !["creator_confirmed", "auto_started"].includes(String(after.startMethod))) return null;
  if (type === "trip_completed" && !["creator_confirmed", "auto_completed"].includes(String(after.completionMethod))) return null;
  return {type, before, after, bidId: assignment.acceptedBidId as string};
}

// Re-read trip plus reciprocal bid/history before claiming and before EACH batch.
export async function tripPushRecipients(port: TripPushPort, tripId: string, event: TripPushEvent): Promise<string[]> {
  if (!id(tripId)) return [];
  const current = await port.loadTrip();
  if (!current || !id(current.creatorId)) return [];
  const bid = await port.loadBid(event.bidId);
  if (!bid || bid.tripId !== tripId || bid.driverId !== event.bidId || bid.driverId === current.creatorId) return [];
  if (event.type === "new_bid") {
    if (current.status !== "open" || current.acceptedDriverId != null || current.acceptedBidId != null ||
        bid.status !== "submitted" || !sameTime(bid.createdAt, event.after.createdAt) ||
        (Array.isArray(current.excludedDriverIds) && current.excludedDriverIds.includes(bid.driverId))) return [];
    return [current.creatorId];
  }
  const after = event.after;
  // Drop out-of-order events, including trips that have reopened and been reassigned.
  if (current.creatorId !== after.creatorId || current.status !== after.status ||
      !sameTime(current.updatedAt, after.updatedAt) || current.acceptedDriverId !== after.acceptedDriverId ||
      current.acceptedBidId !== after.acceptedBidId) return [];
  if (event.type === "trip_cancelled" || event.type === "trip_reopened") {
    const before = event.before!;
    const history = await port.loadCancellation(event.bidId);
    const byCreator = event.type === "trip_cancelled";
    const actor = byCreator ? before.creatorId : before.acceptedDriverId;
    if (!history || history.tripId !== tripId || history.previousStatus !== "accepted" ||
        history.resultingStatus !== after.status || history.cancelledByUid !== actor ||
        history.cancelledByRole !== (byCreator ? "creator" : "driver") ||
        current.lastCancellationBy !== actor || !sameTime(history.cancelledAt, current.lastCancellationAt) ||
        !sameTime(current.lastCancellationAt, after.lastCancellationAt) ||
        bid.status !== (byCreator ? "trip_cancelled" : "cancelled")) return [];
    return [byCreator ? before.acceptedDriverId as string : current.creatorId];
  }
  if (!assigned(current) || bid.status !== "accepted" || bid.driverId !== current.acceptedDriverId) return [];
  const driver = current.acceptedDriverId as string;
  switch (event.type) {
    case "bid_accepted": return [driver];
    case "trip_start_requested": case "trip_end_requested": return [current.creatorId];
    case "trip_started": return after.startMethod === "creator_confirmed" ? [driver] : [current.creatorId, driver];
    case "trip_completed": return after.completionMethod === "creator_confirmed" ? [driver] : [current.creatorId, driver];
    default: return [];
  }
}

export async function deliverTripPush(port: TripPushPort, tripId: string, event: TripPushEvent | null): Promise<string> {
  try {
    if (!event) return "ignored";
    const recipients = await tripPushRecipients(port, tripId, event);
    if (!recipients.length || !await port.claim()) return "ignored";
    let failed = false;
    for (const uid of recipients) {
      const result = await deliverPushRecipient(port, uid,
        async () => (await tripPushRecipients(port, tripId, event)).includes(uid),
        tokens => tripPushPayload(event.type, tripId, tripPushBodies[event.type], tokens));
      if (result === "failed") failed = true;
    }
    return failed ? "failed" : "attempted";
  } catch (_) { return "failed"; }
}

export function firestoreTripPushPort(db: Firestore, messaging: Messaging, tripId: string,
  eventKey: string): TripPushPort {
  const trip = db.collection("trip_posts").doc(tripId);
  // Stable source commit identity, not invocation ID; inaccessible to clients.
  const key = createHash("sha256").update(eventKey).digest("hex");
  return {...firestorePushPort(db, messaging, tripId, trip.collection("push_delivery").doc(key)),
    loadBid: async bidId => (await trip.collection("bids").doc(bidId).get()).data(),
    loadCancellation: async bidId => (await trip.collection("cancellations").doc(bidId).get()).data(),
  };
}
