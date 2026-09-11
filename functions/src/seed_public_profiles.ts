// Operator-only projection initialization for existing users/reviews. Not an endpoint.
// Does not update private users, ratings, trips, references, or statistics.
import {initializeApp} from "firebase-admin/app";
import {getFirestore, type QueryDocumentSnapshot} from "firebase-admin/firestore";
import {syncPublicProfile, syncPublicReview} from "./public_profiles";

async function main(): Promise<void> {
  const projectId = process.env.GOOGLE_CLOUD_PROJECT;
  if (!projectId) throw new Error("Set GOOGLE_CLOUD_PROJECT explicitly");
  initializeApp({projectId});
  const db = getFirestore();
  for await (const user of db.collection("users").stream() as unknown as AsyncIterable<QueryDocumentSnapshot>) {
    await syncPublicProfile(db, user.id);
  }
  for await (const rating of db.collectionGroup("ratings").stream() as unknown as AsyncIterable<QueryDocumentSnapshot>) {
    const trip = rating.ref.parent.parent;
    if (trip?.parent.id === "trip_posts") await syncPublicReview(db, trip.id, rating.id);
  }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
