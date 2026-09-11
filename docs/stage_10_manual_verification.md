# Stage 10 manual verification

## Private trip chat and manual location verification

Not performed by Codex. Before testing, resolve the two new Flutter dependencies (`geolocator ^14.0.3`, `url_launcher ^6.3.2`) yourself using your normal dependency workflow; review the resulting lockfile without upgrading unrelated packages. Deploy the updated Firestore rules manually. Provision a collection-scope composite index on collection ID `messages` with `assignmentDriverId` ascending and `createdAt` ascending, and wait until it is ready. Driver queries filter by authenticated assignmentDriverId and order by createdAt; creator queries order all their trip's messages by createdAt. No Functions deployment is needed for this chat change. Existing public profile functions/rules must already be deployed for participant names/photos. No production message migration is needed because chat has not been deployed.

Android: verify only fine/coarse location permissions were added, and the installed Flutter compile SDK meets geolocator's documented Android requirement (35+). No Gradle versions were changed. iOS: verify the new When In Use explanation; do not enable background modes or add Always usage descriptions. On your Mac, review the plugin's native target build setting `BYPASS_PERMISSION_LOCATION_ALWAYS=1` as described in the package documentation if needed for foreground-only integration. This repository has no Podfile, so no CocoaPods workflow was invented. Web: test on HTTPS (or a browser-recognized secure localhost context). macOS/Linux GPS sharing returns a friendly unsupported message rather than requesting unconfigured native permissions.

Use creator C, accepted performing driver D and losing bidder/unrelated driver X; repeat with a partner creator whose parent driverId refers to C. Chat is opened from existing lifecycle/completed details with Open Trip Chat/View Chat History.

| Scenario | Expected result |
| --- | --- |
| C reads messages from any assignment on their trip | Allowed with existing active account |
| D reads a message with assignmentDriverId == D | Allowed only with existing active account and parent access |
| New driver B reads old driver A text/location by direct get or unfiltered query | Denied, even when B is the current acceptedDriverId |
| A reads B's assignment messages | Denied |
| B queries assignmentDriverId == B ordered by createdAt | Only B's assignment returned; no A text/GPS documents |
| X, a losing bidder, unauthenticated user, or parent-driverId-only actor reads | Denied |
| C or D sends in accepted/start_requested/in_progress/end_requested | Allowed with exact valid payload |
| Open/unaccepted trip create | Denied; creator may still read retained history on reopening |
| Completed/cancelled trip create (text or location) | Denied |
| Completed history; cancelled history where existing parent access/IDs permit it | Read-only; messages retained |
| Message update/delete, including its author | Denied |
| Spoofed senderId/role, wrong message/trip ID, system/admin type | Denied |
| Extra/missing schema fields, client timestamp, whitespace-only/untrimmed/oversized text | Denied |
| Missing, null, empty or wrong assignmentDriverId on create | Denied; must equal the final parent acceptedDriverId |
| Creator sends after reassignment to B with assignmentDriverId == A | Denied, including with otherwise valid text/location |
| Current participant reads an unused message ID before creating it | Missing-document lookup allowed; does not grant access to existing other-assignment documents |
| Text with coordinates; location with text | Denied |
| Non-numeric/non-finite/out-of-range latitude or longitude | Denied |
| Exact -90/90 latitude and -180/180 longitude | Accepted for a valid location message |
| Completion/cancellation and message create in one atomic write | Message create denied by final-parent state check |

These are rule expectations to exercise manually against your deployment/rules-testing process; mocked Dart service tests do not execute rules. Confirm support messages/public reviews remain governed by their existing rules, not the new private trip messages match. Review rule access-call limits with the two related documents/account lookup.

1. Before acceptance, confirm no messages can be sent and no driver can access chat. The creator's own history-read permission does not depend on a current assignment. After acceptance, open as C and D: verify the same trip reference, other participant's safe name/avatar, and an empty conversation. No private phone/email/NIC/evidence fields should be read for the header.
2. Send trimmed text in both directions. Verify real-time delivery, role differentiation, date/time, oldest at top/newest at bottom, and no sample/system messages. Empty and >1000-character messages must fail. Inspect the ten exact fields: id, tripId, senderId, senderRole, assignmentDriverId, messageType, text, latitude, longitude, createdAt. For both senders assignmentDriverId must equal the current acceptedDriverId. Text coordinates must be null and createdAt must be server-produced.
3. Receive a new message while at the latest position: stay at latest. Scroll to older content, receive another message, and use New messages without being forcibly scrolled. Check long text, narrow phones, desktop width, keyboard/landscape, and loading/read-error/retry UI. Null pending timestamps must render safely.
4. Tap Share Location once. Grant permission and obtain coordinates. Inspect one location document (text=null, valid latitude/longitude) and no coordinates in parent trip, public profiles/reviews, support requests or logs. Verify no location writes occur merely by opening the screen, waiting, moving around or backgrounding the app.
5. Test permission denial, permanent denial/browser block, disabled services, permission-dialog timeout and GPS timeout/error. Expect useful messages and zero location writes. Repeated taps after denial must not repeatedly prompt within the same chat session. Change permission in settings and explicitly try again. No background permission should be requested.
6. As the receiver, verify Location shared and Open in Maps; raw coordinates should not be prominently rendered. Tap to open the external map handler/browser with the correct point. Test a missing/blocked launch handler and see the friendly error. No API key or embedded map is needed.
7. Disconnect before send or simulate an uncertain acknowledgement. The UI must show delivery failure and Retry Message; retry must keep the original ID/payload. Repeated text/location retries must create no second document. A failed location-delivery retry must not acquire a fresh GPS position. Reconnect and retry; inspect that no source trip/profile/counter was modified. Pending retry intent is not persisted across leaving/restarting chat; inspect history before manually resending after a restart.
8. Complete the trip while the other participant is in chat. History stays visible; input, Send and Share Location disappear immediately. Direct writes must fail even from stale clients. Complete/reopen the trip while a location permission prompt is open: coordinates must not be sent after the state change. Service transactions and final-state rules are authoritative at races.
9. Exercise Stage 9 reopen/reaccept with C, Driver A and Driver B. While A is assigned, send text and GPS in both directions and confirm A/C can read them. Reopen: C must retain history read-only; A's current chat screen loses access. Accept B: B initially sees an empty history, never A's text/location cards. Send both directions under B and confirm all new records carry B's UID. C sees both histories in time order; B sees only B's assignment. Attempt direct reads of A's known text/location IDs as B, an unfiltered message list, and a query for A's UID: all must fail. A must never read B's messages. Former A's own history access is still conditional on existing parent/history permissions (the current parent rules deny A the assigned trip after B accepts); do not broaden those permissions. Confirm no old records were rewritten or deleted. Retry C's old message ID after reassignment and confirm it is rejected rather than treated as a successful new-assignment send.
10. Regression-check bid privacy, accepted-driver semantics, cancellation/reopen/exclusion, auto-start/auto-complete, completed statistics, ratings, public profile/review projection, support conversations, dashboard identity/order and Sri Lanka CT date generation. No lifecycle/backend implementation was changed for chat.

Coordinates are sensitive data protected by trip access rules, not end-to-end encryption. Authorized readers may retain copies or screenshots; Firestore/device caches are not remotely erased on revocation. Opening Maps intentionally sends the point to that external handler. No coordinates are copied to public or support structures, and no new staff/admin chat permissions were added.

Run the new `test/trip_chat_test.dart` and extended service tests manually when ready. They use injected streams/location callbacks and the existing in-memory SDK transaction harness; no GPS, map app, Firebase integration test or emulator was run by Codex.

## Pre-chat cleanup verification and rollout

All checks below are for the operator; Codex has not run tests, builds, npm, Firebase or Git commands.

Deploy the new `publishUserProfile`, `publishUserReputation`, and `publishWrittenReview` functions in the existing Functions codebase after your normal manual source/build review. They use the existing configured region/service account and require the same Firestore/Eventarc permissions already documented below. They do not alter lifecycle task settings. Deploy the updated rules to enable safe projection reads. Do not grant clients projection-write or broader private-users access.

Existing user/rating documents do not trigger new functions retroactively. After reviewing the source whitelist and obtaining trusted ADC, manually initialize their derived projections (from the functions directory, after your manual build):

```cmd
set GOOGLE_CLOUD_PROJECT=ceylon-travel-mvp
node lib/src/seed_public_profiles.js
```

Use the trusted ADC/impersonation workflow documented below. This script reads users and original ratings, and writes only public projections. It never backfills tripReference or rewrites trips. It can be rerun safely; stop and investigate malformed source ratings rather than granting client write access. Function retries and this tool always read current source state. Profile/review projections are eventually consistent; monitor function failures if they do not appear after source updates.

- Verify a newly generated CT reference during Sri Lanka daytime and at 18:30 UTC midnight rollover. At 2026-09-10 22:30 UTC it must use `260911`. Support reference dates remain UTC; existing references/Firestore IDs must stay unchanged.
- Repeat with tourist and partner creators. At each accepted/active/completed state, creator sees accepted performing driver and that driver sees creator. Parent driverId must never choose the performing profile. Outsiders must not receive assigned-trip access.
- Check both dashboards show the signed-in full name and initials. For an already-resolved safe profile photo URL, check image and failed-load fallback. Unresolved Storage paths must retain initials; empty names use the default avatar.
- Inspect user_public_profiles keys against the exact whitelist. Assert phone/email/NIC/selfie/verification evidence/support/auth fields are absent. Test pending/missing verification shows Not Verified; only trusted approved/verified status shows Verified. No normal client may self-approve or write projection statistics.
- Compare completion/rating fields with canonical reputation data after automatic/manual completion and mutual ratings. Synchronization must not increment counts itself. Missing cancellation count/rate displays Not available rather than a fabricated zero.
- With reviews present, open View Reviews on the opposite participant. Verify stars, original written comment, date and trip reference; no reviewer contact/identity fields should be copied. Verify correct target for both rating directions, and no View Reviews for zero reviews. Original rating creation, aggregation, no-edit and no-delete rules remain intact.
- On both dashboards check all open cards precede active cards, newest createdAt first within each group; completed/cancelled remain outside the active feed. For drivers include marketplace requests, own partner hires and accepted assigned work. Check no duplicates, cancelled-driver exclusion, bid eligibility/privacy, and unchanged Partner Hires/Assigned Work/history links.
- Attempt unauthenticated public-profile/review reads: deny. Active signed-in users may read safe projections, but writes must fail. Cross-user private users reads and support reads must still fail. Deleting a private user removes its public parent; review reads require that parent to exist. Any future trusted erasure/edit of original ratings must also remove/update the corresponding public projection; normal clients cannot edit/delete either source or copy.

Public review text is authored content and may itself contain details the author typed. No structured private fields are projected. Use only photos deliberately approved for profile display; do not populate profilePhotoPath with verification-document URLs. Admin SDK bypasses rules: review the whitelist, source validation and service-account IAM before deployment. New triggers/seeding add Firestore reads/writes and function invocations; existing lifecycle tasks and timing remain unchanged.

Not executed by Codex. Use your separate CMD and Firebase console / rules testing workflow. No integration-test harness, emulator or deployment was run or added.

## Preparation and rule review
Use at least three accounts: creator C (repeat scenarios with tourist AND driver/partner creators), accepted performing driver D, unrelated driver X. Preserve `driverId` on partner posts as the creator/partner; lifecycle permissions use `acceptedDriverId` only.

Deploy/review the new rules yourself before exercising the new clients. Keep existing user private reads owner-only. Review every cross-document metric transaction, exact diff allowlist, deadline boundary, support owner query and custom claim. Unit service tests use a local mocked SDK/channel store; they do not execute Firestore rules.

Queries may require console-created composite indexes:
- `trip_posts`: `acceptedDriverId` + `status` (active `whereIn` and completed queries).
- `trip_posts`: `creatorId` + `status` (completed queries).
- Support list uses `userId` only and sorts locally; thread uses `createdAt` within one request.
`firebase.json` now adds the isolated TypeScript Functions codebase; Flutter project configuration is preserved. No index file was added.

## 1. Lifecycle and role scenarios
Create a new direct trip, submit a real bid and accept it. Repeat with a driver-created partner hire. Check statuses progress `open -> accepted -> start_requested -> in_progress -> end_requested -> completed`. D alone can request start/end. C alone can manually confirm. X cannot read assigned/completed trip details or mutate its lifecycle. A partner creator whose UID is also stored in parent `driverId` must NOT receive performing-driver actions. The accepted performing driver must be distinct from C.

## 2. Three-minute auto-start
D opens accepted trip details and presses Start Trip. Verify the specified popup, including permission to depart immediately; dismiss with OK. Inspect `lifecycle_requests/start.createdAt` and parent `startRequestedAt`, which must be identical server timestamps. `startAutoStartAt` must be exactly 3 minutes later. At this stage `startedAt` and `startMethod` are null. Verify a Cloud Task is scheduled for the stored deadline, then close BOTH apps before the deadline. Before AND after the deadline, direct client `auto_started` writes must be denied. Without reopening either app, inspect Firestore: the backend reaches `in_progress`, `startedAt` is a server commit timestamp, and `startMethod` is `auto_started`. Reopen C and verify the started notice. Repeat with skewed device clocks: they must not affect backend timing. Allow ordinary queue dispatch latency; investigate overdue tasks using logs.

The request has two small transactions because Firestore cannot add a duration to an unresolved `serverTimestamp()`. Phase one anchors server time; phase two publishes the parent request with the exact deadline. Phase two must use an anchor no older than 60 seconds. If interrupted, retry Start Trip while still accepted to refresh the anchor. The anchor is locked after the parent changes state. Do not modify timestamps manually to simulate a successful client request.

## 3. Manual start confirmation
C confirms before the deadline. Check `startedAt == request.time`, `startMethod == creator_confirmed`. D can immediately depart; confirmation is not permission to leave. Reject confirmations from D/X and manual confirmation at/after the deadline. The queued start task must later log a no-op and leave the manual timestamp/method unchanged. At the deadline rules reject manual confirmation; the backend handles timeout independently.

## 4. Thirty-minute auto-complete
After start, D presses End Trip. Inspect end anchor/parent equality and `endAutoCompleteAt == endRequestedAt + 30 minutes`. `endedAt`/`completionMethod` start null. Verify the end task schedule. Reject client automatic writes both early and late. Close all clients before the deadline and inspect Firestore without reopening: the backend completes with server `endedAt`, `auto_completed`, and exactly one increment for both participants. Device time must not affect execution.

## 5. Manual end confirmation
C confirms before the deadline. Check `completed`, server `endedAt` and `creator_confirmed`. Reject end requests from C/X and end requests in any state other than `in_progress`. Repeat two-client concurrent manual/automatic attempts. Retry/refresh a completed trip and verify no duplicate effects.

## 6. Trip Reference
New posts have `CT-YYMMDD-XXXXXX` with a six-character unambiguous random suffix. It is not the internal document ID. Verify the same value in trip details, accepted/active/completed trip screens/cards and attached complaints. Bid acceptance, cancellation/reopen, all lifecycle transitions and ratings must leave it unchanged. Direct attempts to modify it must fail. Legacy posts without a reference show an explicit unavailable label; no reference is fabricated or silently backfilled. New Trip Reference dates use Asia/Colombo (UTC+05:30): 2026-09-10 18:29:59 UTC uses `260910`, while 18:30:00 UTC uses `260911`. Check month/year rollover boundaries too. Existing references remain unchanged, and support reference dates remain UTC.

## 7. Completed counters
Record both C and D's `users/{uid}.completedTripsCount` and `user_reputation/{uid}` before the trip. Acceptance/start/end-request must not increment. Completion must atomically increment both exactly once and set each profile `lastCompletedTripId`. Neither only the profile, only public reputation, nor only the completed trip write should succeed. Test concurrent completions involving the same account and retry backend dispatch. Private phone/email data must never appear in public reputation. Legacy profiles with externally seeded nonzero metrics need a trusted consistent reputation seed before writes; do not relax rules to accept mismatched aggregates.

## 8. Mutual rating
Each participant sees their own independent prompt after completion. C rates D and D rates C using 1-5 integer stars and a required trimmed review <=1000 characters. Verify fixed IDs `creator_to_driver` / `driver_to_creator`; document IDs and `ratedByRole` agree with the actor. Reject X, self-rating, pre-completion submission, empty/oversized comments, stars 0/6/fractional and duplicate directions. Reject editing/deleting a rating. Check target profile/public `ratingsCount`, `ratingStarsTotal`, `averageRating = total/count`. Duplicate attempts cannot increment. Reopen: the user's existing rating replaces their prompt; the other party remains independent.

## 9. Creator complaint
From completed details choose Report / Complain. Verify all ten creator categories, both party IDs, authenticated user ID, trip ID/reference and case `SUP-...` reference. Repeat for a partner creator. No complaint changes reputation, cancellations, bidding eligibility, status, suspension or ranking.

## 10. Driver complaint
D reports the same completed trip. Verify the nine driver categories and correct C/D attachments. Reject unrelated users, swapped participant IDs, wrong-role categories and mismatched reference. General support remains available during active trips; the dedicated trip complaint attachment is limited to completed trips.

## 11. Contact Us
Dashboard Account & Support opens Contact Us and My Support Requests. Verify all seven general categories. Complaint permits an optional manual Trip Reference (no trip lookup or identity claim is inferred); other categories leave it null. Check category-specific acknowledgement appears first in the conversation, followed by the submitted request and replies. Acknowledgement is deterministically rendered from immutable category/reference, not a client-created system message. Registration help currently requires an authenticated account with an active profile.

## 12. Edited contact snapshot
Prefill from the current profile phone. Clear or enter invalid phone: submission fails. Replace with another valid number and submit. Inspect stored `contactNumber` equals the edited trimmed value. A later trusted profile-phone change must not change the historical request. Neither owner nor staff status updates may alter the case snapshot. Actual phone ownership is not verified in this stage.

## 13. Support conversations
List must return only the signed-in user's requests with reference, category, status and last-message time. Submit a user reply; check immutable message fields, `senderRole=user`, timestamp and reciprocal parent `lastMessageId/lastMessageAt/updatedAt`. Reject cross-user reads/list/replies, user `admin/system` roles, message edits/deletes and parent-only timestamp updates. Closed requests reject replies. Staff may reply with `senderRole=admin` only with a trusted `supportAdmin:true` custom claim; parent metadata and message must be committed atomically. Staff may change status with server updatedAt. No staff UI or claim-granting client flow is included. Unclaimed accounts cannot grant themselves this claim through profiles.

## 14. Firestore document and hostile-write checks
Inspect new trip lifecycle fields initialized null; old missing fields parse safely. Review all lifecycle exact allowlists for preservation of route, creator/partner fields, accepted IDs and reference. Attempt arbitrary profile average/count/cancellation/phone changes: deny. Attempt completion missing either counter or public mirror: deny. Attempt rating missing aggregate writes or aggregate writes without rating: deny. Review rule document-access-call limits for the complete atomic batches (including existing cancellation rule branches). Inspect request reference/contact/identity/category/message immutability and report fields. Review support text and phone format validation in both UI/service and rules. Rules do not verify actual phone ownership or factual complaint content.

## 15. Stage 7-9 and UI regression
Manually run your existing/new tests and analyzer/build as desired. Recheck login/email restoration, both registration roles and required phone/driver fields, real trip creation/feeds, bid privacy/acceptance, partner semantics, excluded driver after reopen and previous submitted bid reuse. Open/accepted creator cancellation and accepted-driver cancellation retain mandatory warning, reason validation, penalty boundary and transaction history. Cancellation controls/services/rules must reject `start_requested`, `in_progress`, `end_requested`, `completed`. Verify centered desktop/mobile layout, long references/names/messages, keyboard scrolling, countdowns, loading/error/retry states and back navigation. No maps/payments/tracking were added.

## Future secure profile phone change
No profile-phone update rule was added. A future Profile Settings flow should require the authenticated owner, reauthentication and a narrowly scoped server/rule design; OTP ownership verification can follow. Old case contact snapshots must remain immutable. Never enable unrestricted user profile updates for this feature.

## Backend items deliberately deferred
Trusted lifecycle Cloud Functions/task queues are now implemented. Still deferred: push/FCM, automatic daily email, full admin UI, maps, tracking, fare/commission calculation, payments, phone masking/calling or automatic complaint punishment. Automatic transitions no longer depend on online participants. Backend deployment, IAM, billing and operational monitoring are required. Device-clock skew affects display only. Queues may dispatch late during outages or throttling; exhausted retries need trusted recovery. New references are probabilistically unique, not backed by a global reservation collection. Cancellation metrics remain unavailable until a trusted aggregation/backfill policy is implemented; existing Stage 9 history and archived bid snapshots are preserved.


## Trusted backend setup ? commands for the operator only
None of these commands or checks have been executed by Codex. Use your separate CMD. No `firebase init` is needed: source/configuration are supplied. Review the pinned new Functions dependencies, install them yourself and retain the generated lockfile according to your workflow. Flutter dependency versions are unchanged.

1. Enable Blaze billing for `ceylon-travel-mvp`. Use `asia-southeast1` (Singapore) for Functions/Tasks to match the Firestore database location. The example defaults `LIFECYCLE_REGION` to `asia-southeast1`. Enable Cloud Functions, Cloud Run, Cloud Build, Artifact Registry, Eventarc, Pub/Sub and Cloud Tasks APIs in Google Cloud. Set billing budgets/alerts (alerts do not cap charges).
2. Create the dedicated runtime service account and use it for all three functions. Grant it Firestore access (`roles/datastore.user`) and Eventarc receiving (`roles/eventarc.eventReceiver`). The deployer needs permission to deploy and act as this service account. Do not give application users these IAM roles.

```cmd
cd /d C:\Users\Heenetimulla\taxi_app
set PROJECT_ID=ceylon-travel-mvp
set REGION=asia-southeast1
set LIFECYCLE_SA=trip-lifecycle@%PROJECT_ID%.iam.gserviceaccount.com
gcloud services enable cloudfunctions.googleapis.com run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com eventarc.googleapis.com pubsub.googleapis.com cloudtasks.googleapis.com --project=%PROJECT_ID%
gcloud iam service-accounts create trip-lifecycle --project=%PROJECT_ID% --display-name="Trip lifecycle backend"
gcloud projects add-iam-policy-binding %PROJECT_ID% --member=serviceAccount:%LIFECYCLE_SA% --role=roles/datastore.user
gcloud projects add-iam-policy-binding %PROJECT_ID% --member=serviceAccount:%LIFECYCLE_SA% --role=roles/eventarc.eventReceiver
cd functions
npm install
npm run build
npm test
cd ..
copy functions\.env.example functions\.env.ceylon-travel-mvp
```

Edit the copied environment file: set region/service-account email; leave task URI values empty for the first worker deployment. Do not substitute client credentials or API keys for service-account IAM. Manually install/authenticate Firebase CLI and Google Cloud CLI if not already available; no initialization or package upgrade of the Flutter app is required.

3. Deploy only the workers first so their exact Gen 2 Cloud Run URIs and queues exist. The configured predeploy hook builds TypeScript during your deployment.

```cmd
firebase deploy --only functions:trip-lifecycle:autoStartTrip,functions:trip-lifecycle:autoCompleteTrip --project %PROJECT_ID%
gcloud functions describe autoStartTrip --gen2 --region=%REGION% --project=%PROJECT_ID% --format="value(serviceConfig.uri)"
gcloud functions describe autoCompleteTrip --gen2 --region=%REGION% --project=%PROJECT_ID% --format="value(serviceConfig.uri)"
```

Paste those HTTPS `*.run.app` URIs into `AUTO_START_TASK_URI` / `AUTO_COMPLETE_TASK_URI` in the environment file. Inspect each function's `serviceConfig.service` (or Cloud Run console) to find its actual Cloud Run service name. Set the two CMD variables below to those names, not to guessed camel-case names.

```cmd
set START_SERVICE=REPLACE_WITH_START_CLOUD_RUN_SERVICE_NAME
set END_SERVICE=REPLACE_WITH_END_CLOUD_RUN_SERVICE_NAME
gcloud run services add-iam-policy-binding %START_SERVICE% --region=%REGION% --project=%PROJECT_ID% --member=serviceAccount:%LIFECYCLE_SA% --role=roles/run.invoker
gcloud run services add-iam-policy-binding %END_SERVICE% --region=%REGION% --project=%PROJECT_ID% --member=serviceAccount:%LIFECYCLE_SA% --role=roles/run.invoker
gcloud tasks queues add-iam-policy-binding autoStartTrip --location=%REGION% --project=%PROJECT_ID% --member=serviceAccount:%LIFECYCLE_SA% --role=roles/cloudtasks.enqueuer
gcloud tasks queues add-iam-policy-binding autoCompleteTrip --location=%REGION% --project=%PROJECT_ID% --member=serviceAccount:%LIFECYCLE_SA% --role=roles/cloudtasks.enqueuer
gcloud iam service-accounts add-iam-policy-binding %LIFECYCLE_SA% --project=%PROJECT_ID% --member=serviceAccount:%LIFECYCLE_SA% --role=roles/iam.serviceAccountUser
firebase deploy --only functions:trip-lifecycle:scheduleTripLifecycle --project %PROJECT_ID%
firebase deploy --only firestore:rules --project %PROJECT_ID%
```

The Admin SDK enqueuer uses runtime ADC to authenticate tasks. Confirm the queued HTTP task's OIDC service-account email is the dedicated account and the audience/URI targets the corresponding worker. Cloud Tasks' Google-managed service agent must retain `roles/cloudtasks.serviceAgent` so it can issue identity tokens. Review legacy-project service-agent token permissions if delivery returns 401/403; never resolve this by making workers public. Gen 2 workers need Cloud Run Invoker for that task identity. If your Firebase tooling additionally checks Cloud Functions Invoker, grant it only on the two functions to that identity. Keep `allUsers` and `allAuthenticatedUsers` absent from invocation policies. Private deployment can reset external invoker bindings: recheck/reapply them after any worker redeployment.

Deploy backend and confirm queue/IAM readiness before releasing the changed client/rules together. During migration, do not rely on old client auto writes; new rules deliberately reject them. Existing manual requests/confirmations remain authorized narrowly. No changes to authentication configuration are needed.

## Existing pending trips and exhausted-retry recovery
Firestore triggers are not retroactive. After first deployment, use the supplied operator-only script to enqueue existing `start_requested`/`end_requested` trips. It also recovers pending work after an outage/retry exhaustion; duplicate tasks are harmless. Review the target project and profiles first. The script stops on malformed data so an operator can repair it and rerun; it never alters deadlines or silently discards malformed requests.

Use trusted Application Default Credentials, preferably short-lived impersonation of the dedicated account, with permission to impersonate granted to the operator only. Do not distribute service-account keys. After building Functions and filling the environment file:

```cmd
gcloud auth application-default login --impersonate-service-account=%LIFECYCLE_SA%
set GOOGLE_CLOUD_PROJECT=%PROJECT_ID%
cd functions
node --env-file=.env.ceylon-travel-mvp lib/src/requeue_pending.js
cd ..
```

The operator needs Service Account Token Creator on that account for impersonation. This login is for the trusted maintenance tool, not Flutter. Set `GOOGLE_CLOUD_PROJECT` explicitly as above; ensure the environment file uses the same project/region. Tasks for already-past deadlines dispatch promptly, then workers independently enforce the authoritative due check. Do not edit status or backdate timestamps as a recovery shortcut.

## Backend security, race and failure scenarios
- With both clients offline, verify both deadlines cause transitions and log `changed`. Reopening only displays the persisted result.
- Manually confirm before each deadline, record timestamps/method, and let the queued task execute: it must log `noop` and preserve them. For completion, verify all four private/public counts exactly once.
- Using trusted queue tooling, dispatch a duplicate task body `{tripId}` and invoke concurrently near a manual confirmation. Only one parent transaction can win; repeat counters/references/ratings/cancellations checks. A start task must never increment completed counts.
- Force an early trusted test dispatch without editing stored deadlines: it must fail for retry without changing data. Direct ordinary-client automatic writes must fail at any time. Unauthenticated HTTP or Firebase-user-token requests to task URLs must fail IAM checks. Payloads with extra status/user/deadline fields or invalid IDs must reject.
- Verify out-of-order event delivery rereads current state, deleted/advanced trips no-op, invalid assignment/deadline fails safely, and a missing/mismatched profile leaves the trip AND every counter unchanged. Repair metrics through trusted operations only.
- Test temporary enqueue failure and restore permissions: event retry must enqueue. Test transient worker failure: Cloud Tasks retries without partial writes. Do not leave deliberate IAM failures in production.
- Review `functions/test/lifecycle.test.ts` and run it manually; these are in-memory transaction tests, not IAM, Cloud Tasks, Firestore rules or deployed integration tests. Manually run the updated Dart tests separately. The support conversation test now scrolls the outer ListView to build the lazy input/button; acknowledgement, staff reply and submitted trimmed text assertions remain.
- Create Cloud Logging alerts for `Lifecycle enqueue failed` and `Lifecycle task failed`, monitor queue oldest task age/retry counts/dispatch failures, and operationally inspect overdue pending trips. Tasks/events have finite retention/retries; maintain an operator recovery procedure. Queue/concurrency limits can introduce latency under load. No exact-to-the-second execution guarantee is claimed.
- Billing includes Functions/Cloud Run execution, Firestore reads/writes, Cloud Tasks, Eventarc and logs. Duplicate events can enqueue redundant no-op tasks and add cost. Tune limits after observing real traffic, without introducing a client timeout writer.

References: [Firebase task queue setup/IAM](https://firebase.google.com/docs/functions/task-functions), [Firestore events and delivery caveats](https://firebase.google.com/docs/functions/firestore-events). All configuration, syntax, permissions, rules access budgets and real deployment behavior remain for manual verification.
