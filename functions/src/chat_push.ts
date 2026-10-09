import {DocumentReference, FieldPath, FieldValue, Firestore, Timestamp} from "firebase-admin/firestore";
import {Messaging, MulticastMessage} from "firebase-admin/messaging";

type Data = Record<string, unknown>;
const id = (v: unknown): v is string => typeof v === "string" && v.length > 0 && v.length <= 1500 && !v.includes("/");
const states = ["accepted", "start_requested", "in_progress", "end_requested", "completed", "cancelled"];

// Recompute from the CURRENT assignment, never from a recipient supplied by a client.
export function chatRecipient(tripId: string, messageId: string, trip: Data | undefined,
  message: Data | undefined): string | null {
  if (!trip || !message || !id(tripId) || !id(messageId) || message.id !== messageId ||
      message.tripId !== tripId || !id(trip.creatorId) || !id(trip.acceptedDriverId) ||
      !id(trip.acceptedBidId) || trip.creatorId === trip.acceptedDriverId ||
      !states.includes(String(trip.status)) || message.assignmentDriverId !== trip.acceptedDriverId ||
      !(message.createdAt instanceof Timestamp)) return null;
  if (message.messageType === "text") {
    if (typeof message.text !== "string" || !message.text.trim() || message.text.length > 1000 ||
        message.text.trim() !== message.text || message.latitude !== null || message.longitude !== null) return null;
  } else if (message.messageType === "location") {
    if (message.text !== null || typeof message.latitude !== "number" || typeof message.longitude !== "number" ||
        !Number.isFinite(message.latitude) || !Number.isFinite(message.longitude) ||
        Math.abs(message.latitude) > 90 || Math.abs(message.longitude) > 180) return null;
  } else return null;
  if (message.senderId === trip.creatorId && message.senderRole === "creator") return trip.acceptedDriverId;
  if (message.senderId === trip.acceptedDriverId && message.senderRole === "driver") return trip.creatorId;
  return null;
}

export function chatPushPayload(tripId: string, tokens: string[]): MulticastMessage {
  return tripPushPayload("trip_chat", tripId, "You have a new trip message", tokens);
}

export function tripPushPayload(type: string, tripId: string, body: string, tokens: string[]): MulticastMessage {
  return notificationPayload(type, {tripId}, body, tokens);
}

export function notificationPayload(type: string, identifiers: Record<string, string>, body: string,
  tokens: string[]): MulticastMessage {
  return {tokens, notification: {title: "Ceylon Travel", body},
    data: {type, ...identifiers},
    android: {priority: "high", ttl: 5 * 60 * 1000, notification: {
      channelId: "ceylon_travel_trip_chat", sound: "default", icon: "ic_stat_trip_chat",
      visibility: "private", tag: `${type}_${Object.values(identifiers).join("_")}`,
    }}};
}

export const invalidToken = (code?: string): boolean =>
  code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token";

export interface PushToken { id: string; token: string }
export interface PushDeliveryPort {
  // A durable, server-only at-most-once attempt marker, shared by trigger redeliveries.
  claim(): Promise<boolean>;
  tokens(uid: string): AsyncIterable<PushToken[]>;
  send(payload: MulticastMessage): Promise<{responses: {success: boolean; error?: {code: string}}[]}>;
  removeIfUnchanged(uid: string, token: PushToken): Promise<void>;
}
export interface ChatPushPort extends PushDeliveryPort {
  loadTrip(): Promise<Data | undefined>;
}

export async function deliverChatPush(port: ChatPushPort, tripId: string, messageId: string,
  message: Data | undefined): Promise<"ignored" | "attempted" | "failed"> {
  try {
    const recipient = chatRecipient(tripId, messageId, await port.loadTrip(), message);
    if (!recipient || !await port.claim()) return "ignored";
    return await deliverPushRecipient(port, recipient,
      async () => chatRecipient(tripId, messageId, await port.loadTrip(), message) === recipient,
      tokens => chatPushPayload(tripId, tokens));
  } catch (_) {
    return "failed";
  }
}

// Shared delivery/cleanup for chat, bids and lifecycle notifications. Callers
// claim a durable attempt first and supply their own current-state authorization.
export async function deliverPushRecipient(port: PushDeliveryPort, recipient: string,
  authorized: () => Promise<boolean>, payload: (tokens: string[]) => MulticastMessage,
): Promise<"ignored" | "attempted" | "failed"> {
  try {
    const seen = new Set<string>();
    let failed = false;
    for await (const page of port.tokens(recipient)) {
      const devices = page.filter(device => {
        if (seen.has(device.token)) return false;
        seen.add(device.token);
        return true;
      });
      if (!devices.length) continue;
      // Re-read immediately before EVERY send, including later device pages.
      if (!await authorized()) return "ignored";
      const result = await port.send(payload(devices.map(d => d.token)));
      for (let i = 0; i < result.responses.length; i++) {
        if (invalidToken(result.responses[i].error?.code)) await port.removeIfUnchanged(recipient, devices[i]);
        else if (!result.responses[i].success) failed = true;
      }
    }
    return failed ? "failed" : "attempted";
  } catch (_) {
    // A notification failure never changes/deletes a chat message or retries its write.
    return "failed";
  }
}

export function firestoreChatPushPort(db: Firestore, messaging: Messaging, tripId: string,
  messageId: string): ChatPushPort {
  const trip = db.collection("trip_posts").doc(tripId);
  const attempt = trip.collection("messages").doc(messageId).collection("push_delivery").doc("chat");
  return firestorePushPort(db, messaging, tripId, attempt);
}

export function firestorePushPort(db: Firestore, messaging: Messaging, tripId: string,
  attempt: DocumentReference): ChatPushPort {
  const trip = db.collection("trip_posts").doc(tripId);
  return {...firestoreDeliveryPort(db, messaging, attempt), loadTrip: async () => (await trip.get()).data()};
}

export function firestoreDeliveryPort(db: Firestore, messaging: Messaging,
  attempt: DocumentReference): PushDeliveryPort {
  return {
    claim: () => db.runTransaction(async tx => {
      if ((await tx.get(attempt)).exists) return false;
      tx.create(attempt, {attemptedAt: FieldValue.serverTimestamp()});
      return true;
    }),
    async *tokens(uid) {
      if ((await db.collection("account_deletion_blocks").doc(uid).get()).exists) return;
      const collection = db.collection("users").doc(uid).collection("fcm_tokens");
      let cursor: string | undefined;
      while (true) {
        let query = collection.orderBy(FieldPath.documentId()).limit(500);
        if (cursor) query = query.startAfter(cursor);
        const page = await query.get();
        yield page.docs.flatMap(doc => {
          const d = doc.data();
          return d.enabled === true && d.platform === "android" && d.permission === "authorized" &&
            typeof d.token === "string" && d.token.length > 0 && d.token.length <= 4096 &&
            d.lastSeenAt instanceof Timestamp && d.lastSeenAt.toMillis() >= Date.now() - 30 * 86400000
            ? [{id: doc.id, token: d.token}] : [];
        });
        if (page.size < 500) return;
        cursor = page.docs[page.size - 1].id;
      }
    },
    send: payload => messaging.sendEachForMulticast(payload),
    removeIfUnchanged: (uid, device) => db.runTransaction(async tx => {
      const ref = db.collection("users").doc(uid).collection("fcm_tokens").doc(device.id);
      // Don't delete a fresh token that replaced the rejected token during delivery.
      if ((await tx.get(ref)).data()?.token === device.token) tx.delete(ref);
    }),
  };
}
