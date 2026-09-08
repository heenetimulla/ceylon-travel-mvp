# Stage 8 bidding: manual verification and deferred work

These changes are local. No tests, analyzer, builds, Git commands, or Firebase deployment were run by the agent. Test files were updated/added for later execution by the owner.

## Registration and bid data

- Register both a Tourist and a driver. Blank/whitespace phone numbers, letters, misplaced plus signs, unbalanced parentheses, and numbers outside 7-15 digits must be rejected. Local/international numbers with spaces, hyphens, and parentheses are accepted. Saved phoneNumber has trimmed edges. This does not verify phone ownership; no SMS or phone authentication was added.
- A new driver must choose one of the seven standard primary vehicle types. There is no Any choice. Existing profiles are not migrated or restricted by their old vehicle type.
- Submit a new bid using a different vehicle type AND vehicle number than the profile. It must succeed. Both bid values describe the vehicle offered for that trip; neither is compared with profile values.
- Confirm exactly 16 fields on new bids: id, tripId, driverId, driverName, driverRating, completedTrips, cancellationRate, priceAmount, vehicleType, vehicleDetails, vehicleNumber, estimatedTripMinutes, message, status, createdAt, updatedAt.
- Confirm details/number are trimmed and limited to 160/40 characters. Number must be explicitly entered for each bid and is never prefilled from a profile. Duration remains 1-10080 minutes to complete the trip.
- Existing Task 1 bids lacking vehicleNumber remain readable and show Not provided. No number is invented or copied from a profile, and no stored documents are migrated. Use fresh bids to verify the final schema. The acceptance update preserves old bid fields as requested.

## Creator and driver privacy

- Use a Tourist creator, a partner creator, two bidding drivers, and an unrelated Tourist. All accounts used for positive checks need active profiles.
- Each creator can GET/LIST bids only beneath their own parent trip. Ownership is checked from stored creatorId. Partner creators can reach their posts through Driver Dashboard > My hire posts > View Details > View Bids. Tourist dashboards keep open and accepted own posts.
- A normal driver can GET only bids/{their UID}, with matching stored driverId. Listing the collection or reading a competitor document must fail, even with a narrowed query. A partner creator may list bids on their own post as creator.
- Drivers cannot bid on their own posts. Duplicate bids stay blocked.
- Signed-out, missing-profile, inactive-profile, and unrelated users must be denied.
- The strict driver own-bid rule checks resource.data.driverId; a nonexistent bid document therefore returns a friendly permission error rather than a server-confirmed null.

## Acceptance and atomic rules

1. Open the creator's bid list and add bids from other clients. Verify live arrivals, chronological order (null timestamps last, ID breaks ties), vehicle fields, loading, empty, error, and Retry states.
2. Cancel the confirmation dialog: no writes. Confirm acceptance: saving feedback, then Bid accepted successfully. The summary must show the chosen driver, price, actual vehicle type/details/number, and estimated trip duration.
3. Inspect the parent: status accepted, acceptedBidId selected bid ID, acceptedDriverId performing driver UID, updatedAt server timestamp. Existing driverId remains the partner creator UID where applicable.
4. Inspect the selected bid: only status and updatedAt change. Losing bids remain submitted in storage but display CLOSED because the parent is accepted.
5. With two sessions for the same creator, attempt two different acceptances concurrently. Exactly one succeeds; the other receives This trip already has an accepted bid. Reopening the list must show the same winner. No other acceptance is enabled.
6. Attempt acceptance on an expired or non-open trip, with a missing/mismatched/non-submitted bid, or as a non-creator. Each must fail without partial writes.
7. Verify rules reject parent-only acceptance, bid-only acceptance, two selected bid updates, changes to price/driver/vehicle fields, changes to trip fields outside the four-field allowlist, and deletes. Both directions use getAfter and verify the old open/unselected state. See [Firebase atomic operations guidance](https://firebase.google.com/docs/firestore/manage-data/transactions#data_validation_for_atomic_operations).
8. After acceptance, new bids fail and the trip disappears from the status == open driver feed. An active performing driver can GET the accepted trip by its known ID; unrelated drivers cannot. Accepted drivers can also use My accepted trips, backed by a query constrained to status == accepted and acceptedDriverId == their UID. Unconstrained accepted-trip queries remain denied. Creators retain access to their own accepted posts.
9. Verify network failures produce friendly messages and Retry recovers. Transactions require connectivity; no offline acceptance is simulated.

## Contact sharing TODO

No secure accepted-party contact-sharing mechanism exists in this flow. No Call button is enabled. users/{uid} remains readable only by that user; phone numbers are not copied into trip posts or bids. TODO: design authorized accepted-trip contact retrieval before adding a native dialer. A native dialer reveals the number. Any masking requires a later proxy/call-relay design, not a UI-only mask.

## Future cancellation compatibility

Bid history and losing bid documents are preserved. CLOSED is derived only while the parent is accepted; it is not written into losing bids. No cancellation or reopen is authorized by these rules yet. A future implementation must explicitly add driver cancellation/reopen/exclusion and selected-bid reset handling, creator cancellation/closure without reopening, required reasons, and the two-hour penalty policy. No cancellation, penalty, fee, notification, trip start/end, payment, or rating action was added here.


## Accepted-driver dashboard access follow-up

Driver Dashboard now has a separate **My accepted trips** card. Its real-time list queries `trip_posts` with BOTH `status == accepted` and `acceptedDriverId == current UID`. It sorts by scheduledAt ascending in memory, with document ID as the tie-breaker. It does not apply an expiry filter, so an accepted assignment remains findable after its scheduled time until a later trip-state flow is implemented.

Each card shows pickup/drop, schedule, passenger and baggage information. View Details opens the real TripDetailsScreen without submit/view-bids actions. Its additional accepted-bid panel uses only BidService.watchDriverBid, which reads `trip_posts/{tripId}/bids/{current UID}`. The panel verifies that this bid matches the parent's selected bid, performing driver and trip, and that the stored bid is accepted. It displays price, vehicle type/details/number and completion duration. No fake bid, creator profile read, phone access, chat, call, cancellation, start/end or other trip action is added.

### Index setup, if requested by Firestore

This query has two equality filters and no server-side orderBy. Existing single-field indexes may be sufficient through index merging. If Firestore reports a missing index, manually create a composite index for collection `trip_posts`, query scope **Collection**, with `status` **Ascending** and `acceptedDriverId` **Ascending**. Wait until it is enabled, then use Retry. There is no scheduledAt index requirement for this query because sorting happens after the securely constrained read. No index or rules were deployed by the agent. See [Firestore index merging](https://firebase.google.com/docs/firestore/query-data/index-overview#use_index_merging).

### Manual verification for this gap

- Accept a bid while the performing driver's accepted-trip list is open: it should appear live and disappear from the open bidding feed. Leave/reopen the dashboard and confirm it remains discoverable.
- Confirm both Tourist-created and partner-created accepted assignments appear for the performing driver, independently of the trip's existing driverId creator field.
- Open View Details and confirm locations, schedule, adult/kid counts, baggage, notes, accepted status and the real own-bid vehicle/price/duration.
- Verify a second driver sees only their own assignments. A query for all accepted trips, a query using another driver's UID, and a GET of another driver's accepted trip must be denied unless the requester independently owns that trip as its creator. Creator access is preserved.
- Confirm competitor bid reads/lists and creator private profile reads remain denied.
- Confirm signed-out, inactive and non-driver profiles cannot use this stream; verify loading, empty, friendly errors and Retry.
- Rules must be updated manually before the new LIST query can work against the live project. Tests were added but not run; no analyze, Git, Firebase or build commands were run for this follow-up.
