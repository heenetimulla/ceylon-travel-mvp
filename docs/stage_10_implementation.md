# Stage 10 implementation summary

## Pre-chat cleanup: safe profiles, identity and active ordering

Trip Reference generation already uses Asia/Colombo (UTC+05:30), with the same six-character alphabet and secure random suffix. Added an explicit Sri Lanka daytime case to the existing midnight/month/year boundary tests. Existing reference serialization and support UTC behavior remain covered. No trips or references are backfilled.

`user_public_profiles/{uid}` contains only `uid`, `fullName`, `profilePhotoPath`, `verificationStatus`, `completedTripsCount`, `cancellationCount`, `cancellationRate`, `averageRating`, `ratingsCount`. `PublicProfile` parses/serializes only this whitelist. Private users remain owner-readable under existing rules; no additional private user reads were authorized.

Trusted `publishUserProfile` and `publishUserReputation` Firestore functions reread private user and existing reputation records in a transaction, replacing the public projection with the whitelist. Identity comes from users; approval comes only from `verification.status` equal to `approved` or `verified` (pending/missing/other states display Not Verified). Metrics use the existing reputation document, or trusted private completion/rating fields when no public reputation exists. Cancellation metrics ONLY use existing public reputation values; missing metrics stay null/Not available. No counter is incremented by synchronization. The projection is eventually consistent after source commits; existing lifecycle and rating transactions remain authoritative and unchanged. Events reread current source state, so retries/out-of-order delivery cannot revert a newer profile.

`publishWrittenReview` reads existing `trip_posts/{tripId}/ratings/{direction}` plus the completed parent and validates the two participants. It writes a deterministic, read-only display projection at `user_public_profiles/{ratedUid}/reviews/{tripId}_{direction}` with only `stars`, `comment`, `createdAt`, `tripReference`. It never creates another rating or changes aggregates. No reviewer UID, contact data or verification evidence is copied. Reviews are queried under the viewed profile, ordered by `createdAt` descending; original rating access/edit/delete rules stay unchanged.

The shared lifecycle screen adds `ParticipantProfileCard` in accepted/start_requested/in_progress/end_requested/completed states. Selection uses creatorId and acceptedDriverId exclusively; outsiders get no participant card. It shows the opposite party's name, avatar, verification, reputation and View Reviews when ratingsCount > 0. The review screen displays written comments, stars, date and reference. Profile streams are retained across countdown rebuilds.

Both dashboards continue using `UserIdentityHeader`, now sharing `ProfileAvatar` with the participant card. Already-resolved public HTTPS photos render with an error fallback. Storage object paths remain initials/default avatars; no Storage resolution or dependencies were added. Dashboard constructor data hooks support focused widget tests without changing authenticated defaults.

`orderedActiveTrips` filters to open/accepted/start_requested/in_progress/end_requested, sorts open first, then active, and sorts newest createdAt first within each group. Missing creation dates sort last; document ID breaks exact timestamp ties only. It copies the input rather than mutating stream data. Tourist and creator feeds use this order. The driver main feed merges existing authorized open marketplace, own partner-hire and accepted-performing-driver streams, deduplicates by internal ID, and applies the same ordering. Existing exclusions, future-schedule marketplace filter, bid permissions and completed/history navigation remain. Own hire cards lead to creator details; assigned cards lead to the existing lifecycle screen; only eligible marketplace cards offer Submit Bid.

New rules grant active signed-in users read-only access to these safe public profiles/review projections; all client writes are denied. Public does not mean unauthenticated access. Lifecycle/security deadlines, support privacy, original ratings and Stage 9 rules are unchanged.

Created: `lib/core/models/active_trip_order.dart`, `lib/core/models/public_profile.dart`, `lib/core/widgets/profile_avatar.dart`, `lib/core/widgets/participant_profile_card.dart`, `functions/src/public_profiles.ts`, `functions/src/seed_public_profiles.ts`, `functions/test/public_profiles.test.ts`, `test/stage_10_cleanup_test.dart`.

Modified for this cleanup: `lib/core/widgets/user_identity_header.dart`, `lib/core/services/trip_post_service.dart`, `lib/screens/tourist/tourist_home_screen.dart`, `lib/screens/driver/driver_home_screen.dart`, `lib/screens/trip/lifecycle_trip_screen.dart`, `functions/src/index.ts` (new projection exports only), `firestore.rules` (new projection matches only), `test/stage_10_models_test.dart`, and both Stage 10 documents. No lifecycle task implementation, reference-generation implementation, dependencies or Firebase project configuration changed in this pass.

Tests added (not run): public schema/privacy, participant selection, name/avatar/verification/statistics/review visibility and content, dashboard identity, active ordering/history exclusion, backend whitelist and deterministic review projection. Source date tests retain suffix/immutable serialization checks.

Deployment and existing-data preparation are required before profiles/reviews populate. See the cleanup verification section in the manual document. The seeding tool writes only derived public documents; it does not rewrite source users, trips, references or ratings. The subsequent private-chat implementation is described below; no embedded maps, payments or admin UI were added.

## Real private trip chat and manual location sharing

The existing placeholder `lib/screens/chat/trip_chat_screen.dart` now displays real Firestore messages; sample messages and demo location actions were removed. No second trip-chat screen was created. The old unused demo `ChatMessage` model is not used by the real chat.

Created `lib/core/models/trip_chat_message.dart`, `lib/core/services/trip_chat_service.dart`, `lib/core/services/trip_location_service.dart`, and `test/trip_chat_test.dart`. Modified the existing chat screen, lifecycle screen (chat navigation only), `firestore.rules` (private messages match/helpers only), `pubspec.yaml`, Android main manifest, iOS Runner Info.plist, `test/stage_10_services_test.dart`, and both Stage 10 documents. No Functions, Cloud Tasks, lifecycle transactions, public-profile projections, support conversation, ratings, dashboard ordering or reference logic changed.

Messages live exclusively at `trip_posts/{tripId}/messages/{messageId}` with exactly:

| Field | Meaning |
| --- | --- |
| id / tripId | Message document ID and internal parent trip ID |
| senderId | Authenticated UID |
| senderRole | creator or driver, derived from the parent relationship |
| assignmentDriverId | Accepted performing driver's UID when the message is created; immutable assignment ownership |
| messageType | text or location |
| text | Trimmed 1-1000 character text; null for location |
| latitude / longitude | Null for text; finite coordinates within [-90,90] / [-180,180] for location |
| createdAt | Firestore server timestamp |

The creator may read all retained messages on their own trip, including across reopening/reacceptance. A driver may read only documents whose assignmentDriverId equals their authenticated UID, subject to existing parent-trip read access and active-account policy. The immutable assignment field proves participation because message creation binds it to the authoritative acceptedDriverId. Parent driverId never grants chat access. Writes are permitted only for the creator/current performing driver in accepted/start_requested/in_progress/end_requested with a valid accepted assignment. Completed/cancelled and reopened histories are read-only. No parent trip read permissions or history navigation were broadened.

Rules require the exact ten-field schema, assignmentDriverId equal to the current acceptedDriverId, matching sender role/UID/IDs, trusted timestamp, trimmed text or valid numeric coordinates, and deny all message updates/deletes. Creation checks the final parent with getAfter, so an atomic completion/cancellation cannot also append a new message to its now-read-only chat. A missing-document get is permitted for current participants solely for transactional send/retry existence checks; an existing document always uses assignment-specific authorization. Coordinates never enter parent trip fields, public profiles, reviews, support or logs.

TripChatService streams creator history with `orderBy('createdAt')` ascending. Driver queries additionally use `where('assignmentDriverId', isEqualTo: authenticatedUid)` on Firestore before ordering; client filtering is only defense in depth. Provision a collection-scope composite index for `messages`: assignmentDriverId ascending, createdAt ascending. Sends reread the trip and message in a transaction, derive assignmentDriverId from the current parent, recheck session/role/state, and create only a previously absent document. Each UI send retains one message ID and payload until acknowledged; explicit retry uses that same ID. An already committed identical document in the same assignment becomes a no-op, including an uncertain result that completed before retry. A conflicting payload or assignment for the same ID rejects. Failed location-delivery retries reuse the same coordinates rather than fetching GPS again. Pending retry state is in memory only; no automatic replay after leaving/restarting the screen. Transactions require connectivity and deliberately do not enqueue offline writes.

The chat observes the parent live: completion removes the text/location controls. On reopen the creator retains chronological history, with no composer or current-driver profile until reassignment; a former driver's screen clears on access loss. Pending sends are bound to the observed acceptedDriverId to reject reassignment races. The header reads only user_public_profiles for the current other participant's name and shared avatar fallback. Existing profile/review controls remain in trip details. Bubbles distinguish sender and show timestamps; invalid documents get a safe unavailable placeholder, and null pending timestamps do not crash. Reversed list layout renders oldest above newest and initially shows the latest; new arrivals do not force a reader away from older messages. Stable keys identify message input, send, share-location and retry controls.

Location uses new dependency `geolocator: ^14.0.3`; map links use `url_launcher: ^6.3.2`. No existing dependency constraints were changed and dependency resolution/lockfile updates were not run. Share Location checks service availability and permission, requests permission at most once per chat service instance when denied, obtains one current position with a 25-second native timeout and bounded outer waits, validates it, rechecks trip state, then sends one location message. Denied/blocked permission, disabled services, timeout, unsupported desktop platforms and lookup failures produce user-facing errors. Android/iOS/web and the plugin's Windows implementation are supported; macOS/Linux location acquisition is deliberately unavailable without new native setup. There is no location stream, background permission, background service or periodic upload.

Android adds only ACCESS_FINE_LOCATION and ACCESS_COARSE_LOCATION. iOS adds only NSLocationWhenInUseUsageDescription. Web geolocation requires a secure context and browser permission. On iOS, review the geolocator Apple plugin's foreground-only build configuration on your Mac (the project currently has no Podfile); do not add Always descriptions/background modes. The package documents BYPASS_PERMISSION_LOCATION_ALWAYS=1 for its native target when needed. No CocoaPods/SPM files were generated or changed here.

Open in Maps creates an encoded HTTPS Google Maps search URI containing the coordinates, then calls launchUrl with externalApplication directly from the tap. The OS may open its associated map handler or a browser. It requires no Maps SDK/API key, and launch failure is visible. Coordinates are disclosed to the selected external maps handler only when this action is used; they are not displayed prominently in the chat.

Privacy is isolated by assignment driver: Driver B never receives Driver A's retained text or GPS documents, and A cannot read B's documents. The creator retains both histories. Former drivers' own history remains bounded by existing parent/history access; this change adds no former-driver navigation or broader parent permissions. This feature is not deployed, so no message migration/backfill is required; all new messages require assignmentDriverId. Isolation is by driver UID as specified, so a future reassignment to the same UID can include that driver's own earlier messages. Standard authorized client caches can retain previously read data; this is access control, not remote erasure or end-to-end encryption.

Retained-chat regression tests cover both drivers' assignment visibility, creator access to both histories, old location suppression, creator retention on reopen, former-driver screen revocation, required assignment parsing/serialization, server query filters/order, authoritative assignment stamping, and rejection of stale/reused assignment sends. Only the chat model/service/screen, chat rules, the two existing chat test files and these two documents were changed for this privacy fix.

Focused tests were added for parse/null/invalid cases, text/coordinate validation and boundaries, participant/state access, safe identity, chronological text/location rendering, map action, read-only completion, access revocation, empty/read-error states, delivery retry IDs, successful manual GPS send, denied/blocked/disabled/timeout cases, permission request limits and service transaction privacy/idempotence. No tests or tools that build/analyze/deploy/install were run. Firestore-rule expectations and real-device checks are in the manual document, not claimed as executed rule tests.

Dependency references: [geolocator setup](https://pub.dev/packages/geolocator), [url_launcher setup](https://pub.dev/packages/url_launcher).

Implementation only. No tests, analyzer, builds, Git commands, Firebase deployment/emulators, integration tests or package upgrades were run. Runtime and rules validation remain manual.

## 1. Files created
- `lib/core/models/readable_reference.dart`
- `lib/core/models/trip_lifecycle.dart`
- `lib/core/models/user_reputation.dart`
- `lib/core/models/support_request.dart`
- `lib/core/models/support_message.dart`
- `lib/core/services/trip_lifecycle_service.dart`
- `lib/core/services/rating_service.dart`
- `lib/core/services/support_service.dart`
- `lib/core/widgets/reputation_summary.dart`
- `lib/core/widgets/trip_lifecycle_panel.dart`
- `lib/screens/trip/lifecycle_trip_screen.dart`
- `lib/screens/auth/account_screen.dart`
- `lib/screens/support/support_screens.dart`
- `test/stage_10_models_test.dart`
- `test/stage_10_services_test.dart`
- `test/stage_10_widgets_test.dart`
- `docs/stage_10_manual_verification.md`
- `docs/stage_10_implementation.md`

## 2. Files modified
- `firestore.rules`
- `lib/core/models/trip_post.dart`, `bid.dart`, `rating.dart`
- `lib/core/services/trip_post_service.dart`
- `lib/core/widgets/trip_post_card.dart`, `bid_card.dart`, `trip_cancellation_button.dart`
- `lib/screens/auth/registration_screen.dart`
- `lib/screens/driver/driver_home_screen.dart`, `accepted_driver_trip_screen.dart`
- `lib/screens/tourist/tourist_home_screen.dart`, `tourist_bid_list_screen.dart`
- `lib/screens/trip/trip_details_screen.dart`, `pending_trip_screen.dart`, `completed_trips_screen.dart`
- `lib/screens/rating/rating_screen.dart`
- `test/trip_post_test.dart`

## 3. Lifecycle states
`open -> accepted -> start_requested -> in_progress -> end_requested -> completed`.
Existing `cancelled`/reopen semantics remain restricted to Stage 9 open/accepted workflows. Performing-driver authority uses `acceptedDriverId`; parent `driverId` is not reinterpreted. Assigned-trip feeds include accepted and active lifecycle states; completed trips have real creator/performance queries.

## 4. Lifecycle fields
TripPost adds nullable `startRequestedAt`, `startAutoStartAt`, `startedAt`, `startMethod`, `endRequestedAt`, `endAutoCompleteAt`, `endedAt`, `completionMethod`, plus `tripReference`. Missing legacy values remain null. New posts serialize lifecycle fields as null.

## 5. Request start
`TripLifecycleService.requestStart` obtains the authenticated UID and transactionally checks the current trip/accepted performing driver. It anchors request time in `trip_posts/{id}/lifecycle_requests/start` using a server timestamp, then publishes `start_requested` with the exact 3-minute deadline. The rule requires the anchor belong to the current performing driver and be at most 60 seconds old. The specified Start request sent popup is shown after success; the driver may leave with the passenger immediately. Anchors cannot be modified after publication; interrupted requests may be retried while still accepted.

## 6. Three-minute auto-start
Creator confirmation before the deadline sets server `startedAt` and `creator_confirmed`. The Firestore `scheduleTripLifecycle` trigger rereads the pending trip and enqueues a private `autoStartTrip` task at its stored deadline. The worker rereads inside a transaction, compares the deadline against Firestore snapshot `readTime`, and writes `auto_started` with server timestamps only when still pending and due. It runs with both clients offline. The UI timer displays countdowns only; snapshots deliver state changes. No push notification was added.

## 7. Request end
Only the performing driver in `in_progress` may call `requestEnd`. An equivalent server-time end anchor publishes `end_requested`, with `endAutoCompleteAt` exactly 30 minutes later and null completion fields. Creator sees the end request and confirmation action.

## 8. Thirty-minute auto-complete
Creator early confirmation sets server `endedAt` / `creator_confirmed`. The Firestore trigger enqueues private `autoCompleteTrip` at the authoritative 30-minute deadline. The Admin SDK worker sets `auto_completed` and updates both private/public completion counters in one transaction. Manual completion retains its existing client transaction and narrow rules. Both paths read the same parent trip, so transaction conflict retries prevent duplicate completion. Queued tasks after manual completion safely no-op.

## 9. Trip Reference
`CT-YYMMDD-XXXXXX`: Sri Lanka local calendar date (Asia/Colombo, UTC+05:30) plus six secure-random characters excluding ambiguous I/O/0/1. For example, 2026-09-10 18:30 UTC produces the date segment `260911`. Support references retain their existing UTC date behavior. This increases entropy beyond the suggested four-character example. Generated once at creation, distinct from the internal Firestore ID, final in the model, serialized unchanged, and excluded from all update allowlists. Existing references are not rewritten or backfilled. Old trips show an explicit unavailable reference rather than a fabricated one. No global uniqueness reservation is implemented.

## 10. Completed counts
Completion atomically updates the trip, both participant profiles and their public reputation mirrors. Each profile increments `completedTripsCount` and stores `lastCompletedTripId`. Rules tie the exact increment to the before/after trip completion and require the public mirror. The trip transition requires both profile increments. Event replay cannot increment an already-completed trip. Transactions read current reputations so concurrent events retry safely.

## 11. Cancellation statistics
Existing trip cancellationCount/history, exclusion/reopen and penalty behavior are preserved. Existing profile `cancelledTripsCount` / `cancellationRate` and bid snapshots are not rewritten. New profiles support `cancellationCount`, but Stage 9 does not reliably aggregate profile totals/rates. New public reputation records therefore start with null cancellation metrics; event writes preserve any existing trusted cancellation metrics, and UI says Not available. Archived bid completion/rating values are explicitly labeled as values at offer time. No complaint changes cancellation metrics.

## 12. Profile reputation fields
Profiles contain `completedTripsCount`, `cancellationCount`, `cancellationRate`, `averageRating`, `ratingsCount`; `ratingStarsTotal` supports exact rating aggregation. Event pointers `lastCompletedTripId`, `lastRatingTripId`, `lastRatingDirection` make specific cross-document updates provable. Registration initializes new metrics to zero; old missing rating fields use zero defaults.

`user_reputation/{uid}` contains only `completedTripsCount`, `ratingsCount`, `ratingStarsTotal`, `averageRating`, nullable `cancellationCount`, nullable `cancellationRate` (clients cannot alter these). Active authenticated users may read these metrics. Private user profiles remain owner-read-only, with no phone/email leakage through reputation.

## 13. Statistics display
Read-only Account & Support, creator trip cards, driver bid cards, live accepted/active/completed trip details. Creator labels use Completed hires; performing-driver labels use Completed trips. Users without a public mirror yet show unavailable reputation on public cards; own profile metrics remain visible. No fake reviews/counts are invented.

## 14. Rating schema
`trip_posts/{tripId}/ratings/{creator_to_driver|driver_to_creator}` stores `id`, `tripId`, nullable legacy `tripReference`, `ratedByUid`, `ratedUserUid`, `ratedByRole` (creator/driver), integer `stars`, required trimmed `comment` (1-1000 chars), server `createdAt`, server `updatedAt`. Existing Rating model is extended; legacy model fields remain for compatibility, while the real screen uses the persisted schema.

## 15. Rating aggregation
One atomic transaction creates the deterministic rating and updates the rated profile/public mirror. `ratingsCount += 1`, `ratingStarsTotal += stars`, `averageRating = total/count`. Duplicate rating documents reject without incrementing. Rules require a completed trip, correct opposite party, authenticated rater, no self-rating, exact fields and reciprocal aggregate writes. Ratings cannot be edited/deleted by clients. Each participant's own stream replaces their prompt with their submitted review independently.

## 16. Creator complaint
Completed-trip Report / Complain action uses the ten specified creator categories, including no-show, started-without-passenger, timing/end errors, behavior, vehicle, safety, payment and other. Transaction reads the current trip and attaches creatorId/acceptedDriverId/internal ID/reference and authenticated complainant. Tourist and partner creators use creatorId equally.

## 17. Driver complaint
Accepted performing driver receives the nine specified driver categories for passenger no-show, unreachable creator, incorrect details/route, payment issues, behavior, trip changes and other. Same immutable trip/party attachment checks apply. Neither complaint direction creates a rating or automatic punishment.

## 18. Contact Us categories
Complaint, Feedback, Suggestion, Ask a Question, Registration Help, App Usage Help, Other. General Complaint accepts an optional manually entered trip reference without falsely attaching an internal trip/participants. Dashboard Account & Support provides Contact Us and My Support Requests. Active-trip problems can open general support; dedicated attached trip complaints require completion.

## 19. Contact snapshot
Support form loads the current user's profile phone, permits replacement, displays the supplied call notice and uses existing phone validation. Create stores the final trimmed submitted phone. It does not edit users/{uid}. All request update allowlists preserve the historical case contact. No phone settings UI, OTP, provider/configuration changes or broader private-profile permission was added.

## 20. Support request schema
`support_requests/{id}`: `id`, `supportReference`, `userId`, `userRole`, `userName`, `contactNumber`, `category`, nullable `subCategory`, nullable `tripId/tripReference/creatorId/acceptedDriverId`, `subject`, initial `message`, `status`, server `createdAt/updatedAt/lastMessageAt`, nullable `lastMessageId`. Starts open; trusted staff may set open/in_review/resolved/closed. Support references use `SUP-YYMMDD-XXXXXX`.

## 21. Support message schema
`support_requests/{id}/messages/{messageId}`: `id`, `senderId`, `senderRole`, required trimmed `message` (1-4000 chars), server `createdAt`. User service has no sender-role input and always writes user. Trusted staff can write admin through a future staff client; system acknowledgement is not a user-authored message document. Messages cannot be edited/deleted.

## 22. Acknowledgement
The exact category-specific acknowledgement is derived from immutable request category/reference and rendered as the first system-style item. The original request follows it. This avoids granting ordinary clients any system-message write permission. No claim is made that staff have already read a request.

## 23. Conversation
Own-request feed queries `userId == current UID`, sorts by last message locally, and opens a live parent/thread stream. Replies atomically create a message and update parent lastMessageId/lastMessageAt/updatedAt. Closed cases reject replies; resolved cases may still receive user replies without letting users change status. Staff messages render as Support team. Read-only supportAdmin custom claim permission prepares future staff replies/status updates; no full admin interface or claim management was implemented.

## 24. Rules changes
Narrow manual-only lifecycle transition allowlists (client `auto_started`/`auto_completed` writes denied even after deadlines), exact deadline/anchor validation, participant-based assigned/completed read access, immutable reference, reciprocal completion/rating counter rules, deterministic immutable ratings, public-metrics-only reputation documents, owner-only support reads/replies, immutable identity/contact/body snapshots, explicit trusted-staff reply/status permissions. General profile editing remains denied. Existing bid acceptance/Stage 9 cancellation functions remain intact; no arbitrary status update method exists.

## 25. Daily-report-ready data
Every case contains supportReference, tripReference (nullable for general cases), userName, userRole, contactNumber, category, subCategory, message, status, createdAt. References and contact identity remain stable for future report/search/phone review. Staff replies/statuses have compatible schema. No scheduled report/email delivery was built.

## 26. Tests
Created model/preflight, in-memory transaction-service, and widget tests. Coverage includes actor/state permissions and backend deadline boundaries, legacy parsing, references, post-start cancellation protection, both completion counters/idempotence, mutual ratings/validation/duplicates/aggregation, complaint categories and attachments, contact validation/edit snapshot, acknowledgements, support feed/thread/replies/ownership and fixed user sender role. Existing trip schema key assertion was extended; no behavioral tests were removed. Backend tests now cover early/due/late tasks, duplicate/concurrent execution, manual race, invalid payload/assignment/deadline, missing/mismatched profiles and public data privacy. Removed client auto-method tests have equivalent coverage in `functions/test/lifecycle.test.ts`; manual client permission/counter tests remain. The support thread test scrolls its ListView until the lazy reply button is built, preserving acknowledgement, staff reply, accessible input and trimmed send callback assertions. Tests were not run. Service tests mock Firebase SDK host replies, not Firestore rule execution; no integration tests were created.

## 27. Manual verification
See `docs/stage_10_manual_verification.md` for lifecycle/3-minute/30-minute/manual confirmations, references/counters/ratings, both complaint directions, contact edits, support replies, hostile document writes, rule access-call limits and bidding/cancellation regressions. These scenarios have not been performed by Codex.

## 28. Limitations / deferred work
Automatic transitions now use trusted Cloud Tasks and require deployed/configured backend infrastructure, not an online participant. Device-clock skew affects only countdown/action display. Queues are not hard real-time: outages, cold starts and throttling may delay execution; finite retry exhaustion requires operator recovery. A interrupted request anchor expires after 60 seconds and needs a retry while in its original state. References are probabilistically unique and absent on legacy documents. Nonzero externally seeded legacy metrics need trusted matching public reputation initialization; no unsafe client migration/backfill exists. Cancellation totals/rates need a future trusted aggregation policy. General registration help requires an authenticated active profile. No maps/tracking/distance/fare/commission/payments/FCM/daily-email/full-admin/OTP/calling/masking/complaint punishment.

## 29. Manual security review priorities
Review/validate Firestore rules syntax and full atomic access-call budgets before deployment. Exercise malicious writes for every transition, early deadlines, counter-only/completion-only/rating-only writes, duplicate ratings, unrelated participant access, support ownership/status edits and admin/system impersonation. Only trusted infrastructure should grant supportAdmin. Verify private profiles remain inaccessible cross-user; public documents contain metrics only. Verify contact snapshots are immutable and manual references do not imply verified trip ownership. No execution or deployment verification has been performed in this coding-only session.


## Backend architecture correction: files and operation
Created `functions/package.json`, `functions/tsconfig.json`, `functions/.gitignore`, `functions/.env.example`, `functions/src/index.ts`, `functions/src/lifecycle.ts`, `functions/src/requeue_pending.ts`, and `functions/test/lifecycle.test.ts`.
Modified `firebase.json` (Functions codebase only; existing Flutter configuration preserved), `firestore.rules`, `lib/core/models/trip_lifecycle.dart`, `lib/core/services/trip_lifecycle_service.dart`, `lib/screens/trip/lifecycle_trip_screen.dart`, all three `test/stage_10_*_test.dart` files, and both Stage 10 documents. No Flutter dependency, theme, authentication, bidding, cancellation, rating or support production implementation changes.

Flow: accepted driver request -> Firestore server-time anchor -> rule-validated immutable deadline on parent -> retry-enabled Firestore event -> trusted Admin SDK task enqueue -> private IAM-protected worker -> authoritative state/deadline revalidation -> atomic transition.

The client adds exactly 180/1800 seconds to a resolved Firestore server timestamp, never to device time. Rules enforce that exact relationship and anchor ownership/freshness. Backend compares Firestore `readTime` with the stored timestamp, preserving nanoseconds, and writes `FieldValue.serverTimestamp()` for startedAt/endedAt/updatedAt. Scheduling converts the same timestamp to a task schedule time; if rounding dispatches early, the worker throws for retry. No client clock exists in service/preflight authorization; Firestore `request.time` exclusively controls manual confirmation cutoffs.

Task bodies contain only `{tripId}`. Unknown fields, invalid IDs, invalid assignment or incorrectly offset stored deadlines are rejected. Workers do not trust event/client user IDs, methods, status or deadlines. Only the accepted performing driver is counted, never the backward-compatible partner `driverId`. Missing/deleted/advanced trips no-op. Invalid pending data throws and logs for retry/repair. Admin SDK bypasses rules, so review worker validation and IAM together.

The retry-enabled trigger rereads current state to tolerate duplicate/out-of-order events. Enqueue failures propagate; no success marker is prematurely stored. Duplicate queues are intentionally tolerated, including an enqueue success followed by an event retry. The parent status checked inside the completion transaction is the durable deduplication barrier, not `lastCompletedTripId` (which can change on another trip). All four metric documents and the trip are read/written atomically; one winner commits. A queued task after a manual winner changes nothing. Existing rating and cancellation values are preserved; public mirrors are whitelisted to avoid contact-data leaks. Missing profiles or inconsistent private/public metrics fail the entire commit for trusted repair, without partial completion.

Task queue functions use private invocation, bounded concurrency and retry backoff (100 attempts, 24-hour retry setting, 15-300 second backoff). No callable/public automatic transition endpoint is exported. `requeue_pending.ts` is an operator-only ADC script, not a deployed endpoint. Firestore events do not retroactively enqueue documents that were pending before deployment; use that script after deployment and for exhausted retries. It rereads pending documents and enqueues without changing their deadlines or trip data.

See the deployment section in `stage_10_manual_verification.md` for manual commands, URI configuration, IAM, recovery and monitoring. No install/build/test/deploy/init commands were executed. The new package versions are isolated Functions dependencies; no existing package versions were upgraded and no lockfile was generated without installation.

Official API references: [Firebase task queue functions](https://firebase.google.com/docs/functions/task-functions), [task queue options](https://firebase.google.com/docs/reference/functions/2nd-gen/node/firebase-functions.tasks.taskqueueoptions), [Firestore event delivery](https://firebase.google.com/docs/functions/firestore-events). The provided implementation requires deployment and permission verification; source review is not deployment validation.
