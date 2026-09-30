# Stage 12A–D — private workflow push notifications

Implemented in source; compilation, automated tests, deployment and real-device delivery after the latest Stage 12D changes are **pending manual verification**. No commands were run during implementation.

## Development and verification status

DEVELOPMENT:

- Stage 12A chat notifications — **IMPLEMENTED**
- Stage 12B bid notifications — **IMPLEMENTED**
- Stage 12C lifecycle notifications — **IMPLEMENTED**
- Stage 12D workflow/admin/support notifications — **IMPLEMENTED**

VERIFICATION:

- Flutter analyze — **PENDING after latest changes**
- Flutter tests — **PENDING after latest changes**
- Functions build — **PENDING after latest changes**
- Functions tests — **PENDING after latest changes**
- Firestore rules tests — **PENDING after latest changes**
- Firebase deployment — **PENDING for latest Functions**
- Android emulator testing — **PENDING**
- Physical Android testing — **PENDING**

“Implemented” describes source code only, not verified delivery or deployed behavior.

## Scope and platform

Android first. Stage 12A provides private chat push; 12B adds bids and acceptance; 12C adds lifecycle and cancellation updates; 12D adds support and account workflow notices. Existing `firebase_messaging: ^16.7.0`, `flutter_local_notifications: 19.5.0`, other dependency constraints and the `firebase_core_web: 3.10.0` override are unchanged by 12B/C/D. No package or lockfile changes were made in this pass.

**AUTOMATED TEST EXECUTION: PENDING**

**LIVE EMULATOR TESTING: PENDING**

**PHYSICAL ANDROID DEVICE TESTING: PENDING**

**DEPLOYMENT OF NEW FUNCTIONS: PENDING**

Local notifications provide Android foreground display and channel creation. Android compile SDK is at least 35; Java 17 and existing AGP/Kotlin versions remain. Core-library desugaring 2.1.4 is enabled as required by the local-notifications package. No scheduled/exact-alarm notification permissions are added.

iOS, web and desktop runtime messaging are deliberately disabled by a platform guard. Their normal app features remain available. APNs entitlements/keys, web VAPID/service worker setup and platform delivery tests are future work, not completed features.

## Client architecture and session lifecycle

- `main.dart` registers a top-level, entry-point-annotated background handler after Firebase initialization. Setup starts without blocking app startup.
- `FcmService` owns permission requests, token refresh subscription, token persistence, the Android channel, incoming messages and session-bound navigation intents. No token, payload, identity or private content is logged.
- `FcmSession` serializes asynchronous registration/cleanup. A generation guard discards a late token from an obsolete session. Token writes also recheck the live Firebase user inside the Firestore transaction.
- Initial login and app resume fetch the token and update the last-seen timestamp. Null/unavailable tokens and denied permission do not block login. Registration failures are retried at the next login/resume.
- `AuthService.signOut` invokes bounded best-effort cleanup before signing out, while the owner can still delete their private token document. It clears pending navigation, removes only this installation's record, disables auto-init, cancels displayed notifications and deletes this device's FCM token. Other devices are unaffected.
- A persisted previous-owner marker causes token rotation before a different UID can register on this installation. If rotation fails, registration for the new account stops. Unexpected external/offline logout cannot reliably delete the old server document after credentials are gone. Subsequent rotation invalidates that token; the worker cleans invalid tokens and ignores records unseen for 30 days.
- FCM auto-init starts disabled in the manifest and is enabled after an authenticated user grants permission. Android 13+ uses the Messaging permission request. Permission/channel settings can still prevent display or sound; this is not an authentication failure.

## Private device records and Firestore rules

`users/{uid}/fcm_tokens/{installationId}` holds:

| Field | Meaning |
| --- | --- |
| token | Private FCM token, maximum 4096 characters |
| platform | `android` in Stage 12A |
| enabled / permission | Enabled only with `authorized` permission |
| createdAt | Server timestamp, immutable after creation |
| updatedAt / lastSeenAt | Server timestamps refreshed on registration/resume |

The document ID is a random 128-bit installation identifier stored locally, not a raw token. Token rotation updates the same installation document. Multiple installations create independent documents. No `ownerUid` field is accepted; ownership comes exclusively from the authenticated UID in the path. Owner-only read/create/update/delete rules use a narrow field allowlist. Other users and primary/support admins cannot access another user's token records through client SDKs. No public-profile projection is changed; its existing explicit whitelist excludes tokens.

No Stage 11 profile/claim/membership/payment permissions are broadened. No Storage rule changes. No composite index is needed: device records are paged by document ID.

## Backend trigger and assignment privacy

`notifyTripChatMessage` listens to the existing `trip_posts/{tripId}/messages/{messageId}` create path. It uses the existing `LIFECYCLE_REGION` (default `asia-southeast1`) and `LIFECYCLE_SERVICE_ACCOUNT` deployment parameters; it does not change any lifecycle worker.

The worker validates the message shape, IDs, sender role, timestamp and text/location structure. Firestore message-create rules already bind `senderId` to Firebase Auth and `assignmentDriverId` to the current assignment. The worker independently loads the current trip and requires the same assignment and a valid accepted bid. Creator messages target only the current accepted driver; current-driver messages target only the creator. Old-driver/unrelated/malformed messages and missing/reopened trips no-op. Completed/cancelled trips retaining the same assignment can receive an already-created message, consistent with historical chat-read access.

Recipient device records are read server-side in pages of 500. Only enabled Android tokens with authorized permission and a last-seen timestamp within 30 days are sent. Tokens are deduplicated. The trip is read again immediately before **each** multicast batch; an assignment change aborts further sends. The sender's device collection is never loaded.

Only `messaging/registration-token-not-registered` and `messaging/invalid-registration-token` remove records. Cleanup transactionally compares the failed token with the currently stored token, preserving any replacement. Transient or invalid-payload errors do not delete device records.

Push contents are always:

```text
title: Ceylon Travel
body: You have a new trip message
data: type=trip_chat, tripId=<id>
```

No message text, names, contact details, locations, evidence, payment fields or credentials enter the payload. A five-minute TTL limits stale delivery. Channel: `ceylon_travel_trip_chat`, name: `Trip & Chat Notifications`, high importance, default sound, private lock-screen visibility and a monochrome notification icon. Notifications of the same type for the same trip replace the existing tray entry.

### Delivery limits (not exactly-once delivery)

A transaction creates `trip_posts/{tripId}/messages/{messageId}/push_delivery/chat` before sending. This server-only marker prevents concurrent/redelivered events from causing another application-level attempt. FCM sending cannot be atomic with a Firestore transaction. This implementation prefers at-most-once attempts: a crash or FCM failure after claiming can lose a notification. It does not retry ambiguous sends or claim guaranteed delivery. The durable chat and unread indicator remain authoritative and unchanged. Marker cleanup/retention automation is not part of Stage 12A.

Likewise, a notification already handed to FCM/Android cannot be recalled if an assignment or account changes immediately afterward. The worker never selects an old driver from stale message data and revalidates just before sending, but cannot provide an atomic assignment-plus-external-delivery guarantee. Content is generic; foreground display and notification taps revalidate current access. An offline logout may leave an already queued generic system notification visible until cancellation/expiry. No notification grants access to chat.

## Foreground, background and taps

- Foreground: validate current session, operational profile and assignment with authenticated server reads, then display one local notification. Message-ID deduplication avoids repeated foreground callbacks. Foreground notifications may appear while the exact chat is already open; no reliable active-route tracking is added in this stage. Unread/read acknowledgement behavior is unchanged.
- Background/terminated: Android displays FCM notification payloads; the top-level handler initializes Firebase but does not show a second local notification or modify unread state. Force-stopped apps may require reopening before delivery resumes.
- FCM notification taps (`onMessageOpenedApp`/`getInitialMessage`) and local-notification taps enter a UID-bound pending-intent layer. The splash screen marks navigation ready only after its normal session routing completes.
- The existing app-root navigation host opens a guarded destination. It rechecks operational account state, reads the trip from the server through normal Firestore authorization (no cached-assignment fallback), verifies the intent's allowed role/status, then uses the existing chat, creator bid-list or lifecycle screen. Missing/reassigned/unauthorized trips return to the existing home/root route with a safe notice, never payload-derived private data. Logout/user switching clears pending intents and removes protected content. A session generation also rejects a late lookup after switching away and back to the same UID. Signed-out taps are discarded rather than carried into a future unrelated login.

## Stage 12B/C event selection and delivery

`notifyTripBidCreated` listens to `trip_posts/{tripId}/bids/{bidId}` creates.
`notifyTripTransition` listens to updates of `trip_posts/{tripId}`. Both use the existing region/service-account parameters. They do not change bids, lifecycle timestamps, deadlines, cancellation transactions, profiles or unread counts.

| Type | Authoritative event | Recipient | Tap destination after server validation |
| --- | --- | --- | --- |
| `new_bid` | Valid submitted bid, trip still open | Creator only | Creator's bid list, if still open |
| `bid_accepted` | open → accepted, reciprocal accepted bid | Current accepted driver only | Current lifecycle/detail screen |
| `trip_start_requested` | accepted → start_requested | Creator only | Lifecycle/confirmation screen |
| `trip_started` | start_requested → in_progress | Driver for creator confirmation; both participants for `auto_started` | Current lifecycle screen |
| `trip_end_requested` | in_progress → end_requested | Creator only | Lifecycle/confirmation screen |
| `trip_completed` | end_requested → completed | Driver for creator confirmation; both participants for `auto_completed` | Completed lifecycle/detail screen |
| `trip_cancelled` | accepted → cancelled by creator | Driver from that exact cancelled assignment | Home: cancellation revoked driver access to the parent trip |
| `trip_reopened` | accepted → open by assigned driver | Creator only | Creator bid list, if still open |

Cancelling an open/unassigned trip has no driver recipient. Unknown transitions/methods, malformed bids, missing trips, unmatched reciprocal bids/history and obsolete events no-op. The parent legacy `driverId` is never used to choose a performing driver, including partner-created trips.

Cancellation intentionally clears `acceptedDriverId` and `acceptedBidId`. The notification worker checks the before-state against the immutable `cancellations/{acceptedBidId}` record, actor/role, resulting status, exact cancellation timestamp and cancelled bid. This allows the creator's cancellation to notify the affected driver without retaining operational access. Reopen events notify only the creator. Current state is re-read before each recipient/device batch; a newer assignment/status or changed event timestamp suppresses obsolete transition delivery.

`chat_push.ts` supplies shared payload creation, paged token reads, per-recipient token deduplication, multicast delivery and compare-before-delete invalid-token cleanup. Existing Stage 12A chat marker paths and recipient validation remain. `trip_push.ts` supplies event-specific policy. Transition markers are under `trip_posts/{tripId}/push_delivery/{sha256Key}`. The key uses event type and Firestore source commit seconds/nanoseconds; bid markers also include bid ID and create time. A transaction claims the whole logical event before sending to any recipient. Concurrent/redelivered triggers therefore cannot create another attempt. Client access remains denied by existing default-deny rules; no new rules/indexes are required.

As in 12A, this is **at-most-once send attempts, not guaranteed delivery**. Failure/crash after claiming can lose one or more recipients' pushes; ambiguous sends are not automatically repeated. Both new triggers use `retry: false`. Permanent invalid/unregistered tokens are removed; transient errors preserve tokens. The durable trip/bid state remains authoritative. An assignment can still change after the final read and before external FCM delivery; already queued pushes cannot be recalled. Generic content, five-minute TTL and tap authorization limit the consequences. Strict transition timestamp matching may deliberately drop an event superseded by another write.

All payloads contain only fixed title/body text plus `type` and `tripId`. They contain no bid price, driver name, vehicle number, cancellation reason, phone, chat text or identity/payment data. Local foreground text comes from the same fixed event catalog, never incoming arbitrary body text.

Foreground validation uses normal authenticated server reads. For creator cancellation, the driver cannot read the now-revoked parent trip: the client validates their owner-readable immutable cancellation record before showing the generic local alert. Tapping still falls back to home and does not grant detail access. Android background/terminated display and channel behavior are unchanged; no duplicate background local notification is added.

## Source tests added (not executed)

- `functions/test/chat_push.test.ts`: sender exclusion, current-driver/creator routing, old/unrelated driver rejection, multiple devices, malformed/missing input, privacy-only contents, invalid token selection, assignment recheck, duplicate attempts and contained FCM failure.
- `test/fcm_session_test.dart`: initial registration, refresh, logout, pending-token races during switches/logout, null token, recovery after failure and strict session-bound intent parsing.
- `functions/test/trip_push.test.ts`: bid/transition recipients, creator/manual versus automatic transitions, cancellation history, reciprocal bid checks, old assignments and stale commits, malformed/missing data, concurrent attempts, multiple devices, payload privacy, transient/permanent FCM failures and contained transport errors.
- `test/fcm_trip_notifications_test.dart`: every supported intent, creator/performing-driver restrictions, stale assignments, session generation, logout clearing, cancellation fallback policy and existing bid/lifecycle/chat destination selection. These are deterministic source tests; they do not claim live platform delivery coverage.
- `functions/test/workflow_push.test.ts`: Stage 12D audiences, Auth claim checks, support sender/owner binding, acknowledgement exclusion, application states/revisions, payment proof versus quote, identity decisions, membership eligibility, founding singleton delivery key, staff discovery, revocation during send, multiple devices, duplicate attempts, invalid-token cleanup and payload privacy.
- `test/fcm_workflow_notifications_test.dart`: every Stage 12D intent, owner/staff authorization, application and payment routing, current operational eligibility, founding event access, session-switch/revocation races, logout clearing and missing/denied documents. Fake readers avoid Firebase network tests.
- `rules-tests/fcm_tokens.test.mjs`: owner CRUD, private reads, cross-account/admin/anonymous denials, field validation, multiple devices and backend-only delivery markers. Stage 12D adds default-deny coverage for staff candidates and workflow delivery markers, including primary/support admin clients and forged staff writes. Rules test script includes both this suite and the existing lifecycle suite. Emulator-only tests require an explicitly configured local endpoint.

## Manual setup and verification — all pending

1. Resolve Flutter dependencies manually; review/commit the generated lockfile. Run analyzer, Flutter tests and Android debug/release builds yourself. Verify local-notification resources survive release shrinking. No unrelated dependency upgrade is intended.
2. Build/test Functions manually, including the new chat-push suite. Run the Firestore rules suites against the emulator and retain the existing lifecycle regression checks.
3. Confirm Android package `lk.ceylontravel.app`, Firebase project and `google-services.json` match. Use a physical Android device or emulator with working Google Play Services. No console notification campaign, topic or sender key in Flutter is needed.
4. In Firebase/Google Cloud, confirm Firebase Cloud Messaging HTTP v1 API is enabled. Ensure the configured runtime service account has Firestore access and `cloudmessaging.messages.create` (for example the Firebase Cloud Messaging API Admin role, `roles/firebasecloudmessaging.admin`). Use managed Application Default Credentials; do not download/embed service-account keys in the app.
5. The user reports Stage 12A token rules already deployed. Deploy/redeploy `notifyTripChatMessage` with its shared helper refactor and deploy the new `notifyTripBidCreated` and `notifyTripTransition` Functions yourself after verification. Existing billing/Eventarc/Functions requirements still apply. No new rules, indexes, Storage changes, migrations or secrets are needed for 12B/C.
6. Log in as an approved operational creator and driver on separate devices. Grant Android notification permission. Confirm each private installation document has server timestamps and only the documented fields. Confirm a second device creates a second record.
7. Send messages in both directions. Confirm only the other participant receives generic text, correct channel/default sound, and no duplicate foreground/system notification. Test text and location messages without exposing contents.
8. Test foreground, background, locked screen and terminated (not force-stopped) states. Tap each notification and verify the correct current chat opens after startup, with normal unread behavior.
9. Reassign a trip; test an old message/old driver, a reopened trip and notification taps after reassignment. The old driver must not read the new assignment. Verify no unrelated recipient tokens are selected.
10. Test permission denial, network failure, missing/deleted trip and expired/invalid token. Chat sending must still succeed independently of push. Check the generic backend failure log, without logging tokens/payloads.
11. Log out of device A while device B stays logged in. Confirm only A is detached. Switch accounts, including during token registration and after an offline logout; old intents must not open private chat under the new account.
12. Verify pending/suspended/inactive accounts cannot gain operational chat access from a notification. Recheck Stage 10 trip lifecycle and Stage 11 admin/support/private-evidence behavior.
13. Submit bids from multiple drivers: only creator devices should receive generic new-bid alerts. Accept one: only that performing driver's devices should receive acceptance. Repeat with a driver-created partner trip; parent `driverId` must not receive unrelated performing-driver alerts.
14. Request start/end, confirm manually and allow the existing automatic deadlines. Verify recipient table above, all four lifecycle routes, and unchanged three-minute/thirty-minute timing. Complete a trip and tap the completion alert.
15. Cancel as creator and as accepted driver. Creator cancellation should notify only the affected driver and tap should safely return home. Driver cancellation should notify only creator and open the bid list. Reassign and check old-driver tokens are not selected for later transitions/chat. Test a delayed old tap and delayed trigger.
16. Repeat 12B/C events in foreground, background and terminated states, on multiple devices, with permission denied and invalid tokens. Verify default sound/channel, no sensitive lock-screen text, no repeated logical attempt on duplicate source events, and safe fallback for unavailable server state. Inspect backend generic failure logs without adding private payload/token logging.

## Future stages — not implemented

Renewal notifications; APNs/web delivery; exact-open-chat foreground suppression; durable retry/outbox with product-approved duplicate policy; notification preferences/retention management. No analytics, marketing, topics or broadcasts are added.

## Stage 12D sources, audiences and privacy

`workflow_push.ts` adds policy on top of the existing shared delivery helpers. `firestoreDeliveryPort`, `deliverPushRecipient` and `notificationPayload` serve chat, trips and workflow notices; there is no second token store or FCM client. Existing channel, icon, default sound, high importance, five-minute TTL and Android foreground/background behavior remain.

| Event/type | Source | Audience |
| --- | --- | --- |
| `support_new_request` | `support_requests/{requestId}` create | Eligible support staff |
| `support_admin_reply` | Existing `messages/{messageId}` create with `senderRole=admin` | Request owner only |
| `support_user_reply` | Existing message with `senderRole=user` and sender equal to current owner | Eligible support staff |
| `registration_submitted` | Trusted `registration_applications/{uid}/history/{operationId}` create, pending review | Primary admins |
| `registration_correction_required`, `registration_rejected` | Matching current application review history/revision | Owner |
| `registration_approved` | Tourist approval history | Owner |
| `registration_driver_approved` | Driver approval history | Owner, with wording that remaining steps are required |
| `identity_verified`, `identity_action_required` | Successful existing legacy driver identity review operation | Driver owner |
| `payment_submitted` | Successful `submit_payment`, current claim/proof actually submitted | Primary admins |
| `payment_verified`, `payment_rejected` | Successful review of current payment | Payment owner |
| `membership_activated` | Successful existing activation operation, account currently operational | Driver owner |
| `founding_offer_closed` | Existing `admin_notifications/founding_offer_closed` singleton create | Primary admins |

No registration/identity/payment/counter business writes were added. Application review uses its existing immutable history; legacy identity operations use their own successful operation records. Thus an application approval does not also produce a duplicate identity notification. Resubmission is a new submitted revision and can notify reviewers again. Quote creation (`request_payment`) is not proof submission and does not notify reviewers. Activation retries returning `alreadyActivated` cannot produce a second activation notice. Newer application or driver-admin revisions suppress obsolete events.

Support uses authenticated-context create triggers and matches the event principal ID to the immutable stored owner/sender. Message role must be `user` or `admin`; the user must own the request and staff senders must still have `supportAdmin:true`. Missing/mismatched auth context, forged roles, system/acknowledgement roles and missing requests no-op. No messages are generated by these notification Functions; marker/token/staff-index writes are outside message-trigger paths. The parent original message generates only the new-request alert. See [Firebase's auth-context trigger documentation](https://firebase.google.com/docs/functions/firestore-events#access_user_authentication_information). Live verification must confirm Firebase client writes supply matching auth IDs; missing auth context fails closed rather than treating a sender field as proof.

Payloads use only a fixed title/body and a whitelisted `type` plus `supportRequestId`, `accountUid`, `paymentId` (document ID, never human bank/payment reference), or the fixed closure `eventId`. No reasons, phone/email, NIC/DL, amounts, references, support body, bank fields or evidence paths enter notification contents. No new diagnostic payload/token logging is added. The founding event's existing text contains pricing, but the push uses its own fixed generic text and does not copy the event message.

### Trusted staff recipient discovery

`syncNotificationStaffTokens` listens to existing private `users/{uid}/fcm_tokens/{tokenId}` writes and reads that UID's **Firebase Auth** record. It maintains `notification_staff/{uid}` containing only a server timestamp for users with `admin:true` or `supportAdmin:true`; otherwise it removes the candidate. This collection is server-only under existing default-deny rules and does not grant any role. No accountType change or client-writable role flag exists.

Workers page candidate IDs by document ID (500 at a time) and call Auth `getUser` to check current claims/disabled status before loading tokens and again immediately before each multicast send. Candidate entries cannot authorize a revoked/disabled user. Primary review notifications require `admin:true`. Existing support thread/service/rules policy requires **supportAdmin:true**, so a primary admin holding only `admin:true` is not an eligible support reviewer. The existing operator grant tool assigns both claims; this patch does not change claim assignment or support permissions.

After deployment, each reviewer must log in/resume with notification permission enabled so their existing token document refresh bootstraps the staff index. A claim grant to a user without a later token refresh will not automatically discover that reviewer. No full Auth/user-collection scan, backfill command or migration was added. Revocations remain safe even before index cleanup because sends recheck live claims. This design assumes a modest staff population; paged discovery avoids unbounded reads, but sequential recipient delivery shares a 120-second Function timeout. Larger staff broadcasts would need a separate bounded fan-out/outbox design.

### Deduplication and current-state checks

`workflow_push_delivery/{sha256Key}` is server-only. Ordinary keys derive from source path plus Firestore source commit seconds/nanoseconds. The founding event uses one fixed logical key regardless of trigger redelivery/commit metadata; it reuses the Stage 11D event and creates no second counter or cutoff state.

A transactional marker is claimed once for the logical event before recipient sends. The existing **at-most-once attempt** tradeoff remains: a crash, timeout, empty staff index or network failure after claiming can lose notifications; there is no exactly-once guarantee from Firestore to external FCM. New push triggers use `retry:false`; staff-index synchronization alone uses `retry:true` and is idempotent. Source records and audit/history remain intact. No marker retention automation is added. Temporary FCM failures retain tokens; permanently invalid/unregistered tokens are removed only if unchanged. Re-checks cannot recall a notification already handed to FCM before a later claim/account change.

### Stage 12D tap routing

The existing session-bound intent parser and navigation host now handle workflow types. `WorkflowNotificationResolver` checks the same UID/session generation before and after **each** server read and claim-refresh await, stopping further reads immediately after a switch. Fresh claims are checked again after loading. Logout/user switching invalidates pending or in-flight destinations. Invalid/missing/denied records safely return to the existing home/root route.

- Support staff → existing secure admin support detail, requiring `supportAdmin:true`; support owner → existing owner thread. Pending applicants need not be operational to access their own permitted support/application flow.
- Submitted application → current pending application in existing admin account detail, requiring `admin:true`.
- Payment proof → existing admin account detail with payment focus, requiring `admin:true` and the current submitted payment.
- Owner application/identity/payment decisions → reload authoritative `users/{uid}` plus application and driver verification/current payment where relevant. Pending/correction/rejected accounts go to the application flow; approved but non-operational drivers go to verification/payment status; eligible tourists/drivers go to their normal home screen.
- Membership activation → driver dashboard only if the current account passes the existing operational and driver-bidding helpers, including annual expiry. The foreground activation notice is suppressed if no longer eligible.
- Founding closure → existing protected Admin Dashboard after reading the actual singleton event.

The compatibility-named `TripChatPushIntent` now also carries workflow identifiers; it remains the single pending-intent layer. Notification wording never activates accounts or grants document access. No public evidence URLs or new Storage permissions are involved.

### Stage 12D manual setup and verification — all pending

1. Run the deferred Flutter/Functions build and test checks yourself, including all Stage 12A–C regression tests and existing Firestore rules tests. No versions/lockfiles or rules/indexes changed in 12D.
2. Deploy `syncNotificationStaffTokens`, `notifySupportRequestCreated`, `notifySupportReplyCreated`, `notifyRegistrationReviewEvent`, `notifyDriverOperationCompleted`, and `notifyFoundingOfferClosed`; redeploy existing push Functions to include the shared helper changes. Keep existing region/service-account parameters. Runtime identity needs Firebase Auth user-read, Firestore access and existing FCM send permissions. No service-account keys belong in Flutter.
3. Bootstrap reviewer candidates by login/resume with notifications enabled. Inspect server-managed candidate IDs, then verify normal users cannot read/write the candidate/marker collections. Check support-only, primary-only, dual-claim and revoked/disabled staff separately. No new Firebase console campaign, topic or client role field is required.
4. Create support requests and both reply directions on separate devices. Verify sender exclusion, owner binding, exact generic content and no acknowledgement loop. Confirm actual Auth-context IDs match client authors; test missing/mismatched context no-op behavior without logging private contents.
5. Submit/resubmit Tourist and Driver applications; approve, reject and request correction. Check current revision routing, no reason/evidence exposure, and no duplicate approval-plus-identity push. Check legacy identity decisions separately.
6. Request a quote (no reviewer alert), submit proof (admin alert), verify/reject payment (owner alert), then activate membership. Verify payment alone does not imply driver activation. Test stale payment IDs, changed revisions, ineligible/suspended accounts and annual expiry.
7. Exercise founding closure using an isolated test project and the existing authoritative activation flow. Confirm one durable close event and one logical delivery marker, including duplicate delivery. **Existing closure records do not fire a create trigger retroactively**; no production counter reset or backfill is part of this change.
8. Repeat foreground/background/terminated delivery, multiple devices, logout/switch races, claim revocation, missing records, temporary FCM failure and permanently invalid tokens. Confirm Stage 10/11 and Stage 12A–C behavior remains intact. All checks remain pending.

References: [Flutter FCM delivery](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [server authentication](https://firebase.google.com/docs/cloud-messaging/send/v1-api), [token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens), [local notification Android setup](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0).
