# Stage 12A — private trip chat push foundation

Implemented in source; dependency resolution, compilation, automated tests, deployment and real-device delivery are **pending manual verification**. No commands were run during implementation.

## Scope and platform

Android first, trip chat only. `firebase_messaging: 16.1.0` and `flutter_local_notifications: 19.5.0` are pinned. The former declares `firebase_core ^4.3.0`, compatible with the existing `^4.9.0` constraint. Unrelated Firebase constraints and the `firebase_core_web: 3.10.0` override are unchanged. The user must resolve dependencies and review the resulting lockfile; it was not edited manually.

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

No message text, names, contact details, locations, evidence, payment fields or credentials enter the payload. A five-minute TTL limits stale delivery. Channel: `ceylon_travel_trip_chat`, name: `Trip & Chat Notifications`, high importance, default sound, private lock-screen visibility and a monochrome notification icon. Notifications for the same trip replace the existing tray entry.

### Delivery limits (not exactly-once delivery)

A transaction creates `trip_posts/{tripId}/messages/{messageId}/push_delivery/chat` before sending. This server-only marker prevents concurrent/redelivered events from causing another application-level attempt. FCM sending cannot be atomic with a Firestore transaction. This implementation prefers at-most-once attempts: a crash or FCM failure after claiming can lose a notification. It does not retry ambiguous sends or claim guaranteed delivery. The durable chat and unread indicator remain authoritative and unchanged. Marker cleanup/retention automation is not part of Stage 12A.

Likewise, a notification already handed to FCM/Android cannot be recalled if an assignment or account changes immediately afterward. The worker never selects an old driver from stale message data and revalidates just before sending, but cannot provide an atomic assignment-plus-external-delivery guarantee. Content is generic; foreground display and notification taps revalidate current access. An offline logout may leave an already queued generic system notification visible until cancellation/expiry. No notification grants access to chat.

## Foreground, background and taps

- Foreground: validate current session, operational profile and assignment with authenticated server reads, then display one local notification. Message-ID deduplication avoids repeated foreground callbacks. Foreground notifications may appear while the exact chat is already open; no reliable active-route tracking is added in this stage. Unread/read acknowledgement behavior is unchanged.
- Background/terminated: Android displays FCM notification payloads; the top-level handler initializes Firebase but does not show a second local notification or modify unread state. Force-stopped apps may require reopening before delivery resumes.
- FCM notification taps (`onMessageOpenedApp`/`getInitialMessage`) and local-notification taps enter a UID-bound pending-intent layer. The splash screen marks navigation ready only after its normal session routing completes.
- A small app-root navigation host opens a guarded chat destination. It rechecks operational account state, reads the trip from the server through normal Firestore authorization (no cached-assignment fallback), verifies current assignment, then uses `TripChatScreen`. Missing/reassigned/unauthorized trips produce an unavailable screen, never payload-derived private data. Logout/user switching clears pending intents and removes protected chat content. Signed-out taps are discarded rather than carried into a future unrelated login.

## Source tests added (not executed)

- `functions/test/chat_push.test.ts`: sender exclusion, current-driver/creator routing, old/unrelated driver rejection, multiple devices, malformed/missing input, privacy-only contents, invalid token selection, assignment recheck, duplicate attempts and contained FCM failure.
- `test/fcm_session_test.dart`: initial registration, refresh, logout, pending-token races during switches/logout, null token, recovery after failure and strict session-bound intent parsing.
- `rules-tests/fcm_tokens.test.mjs`: owner CRUD, private reads, cross-account/admin/anonymous denials, field validation, multiple devices and backend-only delivery markers. Rules test script includes both this suite and the existing lifecycle suite. Emulator-only tests require an explicitly configured local endpoint.

## Manual setup and verification — all pending

1. Resolve Flutter dependencies manually; review/commit the generated lockfile. Run analyzer, Flutter tests and Android debug/release builds yourself. Verify local-notification resources survive release shrinking. No unrelated dependency upgrade is intended.
2. Build/test Functions manually, including the new chat-push suite. Run the Firestore rules suites against the emulator and retain the existing lifecycle regression checks.
3. Confirm Android package `lk.ceylontravel.app`, Firebase project and `google-services.json` match. Use a physical Android device or emulator with working Google Play Services. No console notification campaign, topic or sender key in Flutter is needed.
4. In Firebase/Google Cloud, confirm Firebase Cloud Messaging HTTP v1 API is enabled. Ensure the configured runtime service account has Firestore access and `cloudmessaging.messages.create` (for example the Firebase Cloud Messaging API Admin role, `roles/firebasecloudmessaging.admin`). Use managed Application Default Credentials; do not download/embed service-account keys in the app.
5. Deploy the narrow Firestore token rules and new `notifyTripChatMessage` Function yourself. Existing billing/Eventarc/Functions deployment requirements still apply. No indexes, Storage rules, migrations or secrets are added for Stage 12A.
6. Log in as an approved operational creator and driver on separate devices. Grant Android notification permission. Confirm each private installation document has server timestamps and only the documented fields. Confirm a second device creates a second record.
7. Send messages in both directions. Confirm only the other participant receives generic text, correct channel/default sound, and no duplicate foreground/system notification. Test text and location messages without exposing contents.
8. Test foreground, background, locked screen and terminated (not force-stopped) states. Tap each notification and verify the correct current chat opens after startup, with normal unread behavior.
9. Reassign a trip; test an old message/old driver, a reopened trip and notification taps after reassignment. The old driver must not read the new assignment. Verify no unrelated recipient tokens are selected.
10. Test permission denial, network failure, missing/deleted trip and expired/invalid token. Chat sending must still succeed independently of push. Check the generic backend failure log, without logging tokens/payloads.
11. Log out of device A while device B stays logged in. Confirm only A is detached. Switch accounts, including during token registration and after an offline logout; old intents must not open private chat under the new account.
12. Verify pending/suspended/inactive accounts cannot gain operational chat access from a notification. Recheck Stage 10 trip lifecycle and Stage 11 admin/support/private-evidence behavior.

## Future stages — not implemented

Bid, acceptance, start/end, cancellation, support, application/payment approval and renewal notifications; APNs/web delivery; exact-open-chat foreground suppression; durable retry/outbox with product-approved duplicate policy; notification preferences/retention management. No analytics, marketing, topics or broadcasts are added.

References: [Flutter FCM delivery](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages), [server authentication](https://firebase.google.com/docs/cloud-messaging/send/v1-api), [token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens), [local notification Android setup](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0).
