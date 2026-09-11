// Trusted operator-only recovery tool; never exported as a deployed endpoint.
// Uses ADC and the same explicit deployment settings as the scheduler.
import {initializeApp} from "firebase-admin/app";
import {getFirestore, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {getFunctions} from "firebase-admin/functions";
import {pendingDeadline} from "./lifecycle";

async function main(): Promise<void> {
  const projectId = process.env.GOOGLE_CLOUD_PROJECT;
  const region = process.env.LIFECYCLE_REGION;
  const serviceAccountId = process.env.LIFECYCLE_SERVICE_ACCOUNT;
  const startUri = process.env.AUTO_START_TASK_URI;
  const endUri = process.env.AUTO_COMPLETE_TASK_URI;
  if (!projectId || !region || !serviceAccountId || !startUri || !endUri) throw new Error("Explicit project, region, task service account and both task URIs are required");
  initializeApp({projectId, serviceAccountId});
  const trips = getFirestore().collection("trip_posts")
    .where("status", "in", ["start_requested", "end_requested"]).stream();
  for await (const snapshot of trips as unknown as AsyncIterable<QueryDocumentSnapshot>) {
    // Re-read immediately before scheduling; workers re-read again transactionally.
    const current = await snapshot.ref.get();
    const trip = current.data();
    if (!trip) continue;
    const phase = trip.status === "start_requested" ? "start" : trip.status === "end_requested" ? "end" : null;
    if (!phase) continue;
    const deadline = pendingDeadline(trip, phase)!;
    const uri = phase === "start" ? startUri : endUri;
    if (!/^https:\/\/[^/]+\.run\.app\/?$/.test(uri)) throw new Error("Invalid worker URI");
    const name = phase === "start" ? "autoStartTrip" : "autoCompleteTrip";
    await getFunctions().taskQueue(`locations/${region}/functions/${name}`).enqueue({tripId: current.id}, {
      scheduleTime: deadline.toDate(), dispatchDeadlineSeconds: 120, uri,
    });
    console.log(`Queued ${phase} for ${current.id}`);
  }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
