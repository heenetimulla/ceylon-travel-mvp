import {strict as assert} from "node:assert";
import {test} from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {publicProfile, syncPublicReview} from "../src/public_profiles";

test("public profile whitelists identity and trusted metrics, excluding verification evidence", () => {
  const user = {fullName: " Test Driver ", profilePhotoPath: null, phoneNumber: "private",
    email: "private", nic: "private", verification: {status: "approved", selfie: "private"},
    cancellationCount: 0, cancellationRate: 0};
  const result = publicProfile("u", user, {completedTripsCount: 48, cancellationCount: 2,
    cancellationRate: 4, averageRating: 4.8, ratingsCount: 31});
  assert.deepEqual(result, {uid: "u", fullName: "Test Driver", profilePhotoPath: null,
    verificationStatus: "verified", completedTripsCount: 48, cancellationCount: 2,
    cancellationRate: 4, averageRating: 4.8, ratingsCount: 31});
});
test("pending verification and absent reliable cancellation data stay unverified/unavailable", () => {
  const result = publicProfile("u", {fullName: "User", verification: {status: "pending"},
    completedTripsCount: 3, cancellationCount: 0, cancellationRate: 0});
  assert.equal(result.verificationStatus, "not_verified");
  assert.equal(result.completedTripsCount, 3);
  assert.equal(result.cancellationCount, null);
  assert.equal(result.cancellationRate, null);
});

for (const direction of ["creator_to_driver", "driver_to_creator"]) {
  test(`review projection uses original rating and the opposite participant: ${direction}`, async () => {
    const target = direction === "creator_to_driver" ? "performer" : "creator";
    const author = direction === "creator_to_driver" ? "creator" : "performer";
    const docs: Record<string, any> = {
      "trip_posts/t": {status: "completed", creatorId: "creator", driverId: "partner",
        acceptedDriverId: "performer", tripReference: "CT-260911-ABC234"},
      [`trip_posts/t/ratings/${direction}`]: {ratedUserUid: target, ratedByUid: author,
        stars: 5, comment: "  Reliable driver  ", createdAt: null, phoneNumber: "private"},
    };
    const writes: Record<string, any> = {};
    const collection = (path: string): any => ({doc: (id: string) => ({path: `${path}/${id}`,
      collection: (name: string) => collection(`${path}/${id}/${name}`)})});
    const db = {collection, runTransaction: async (body: any) => body({
      get: async (ref: any) => ({exists: ref.path in docs, data: () => docs[ref.path]}),
      set: (ref: any, value: any) => { writes[ref.path] = value; },
    })} as unknown as Firestore;
    await syncPublicReview(db, "t", direction);
    await syncPublicReview(db, "t", direction);
    assert.deepEqual(writes, {[`user_public_profiles/${target}/reviews/t_${direction}`]: {
      stars: 5, comment: "Reliable driver", createdAt: null, tripReference: "CT-260911-ABC234",
    }});
    assert.equal(docs[`trip_posts/t/ratings/${direction}`].comment, "  Reliable driver  ");
  });
}
