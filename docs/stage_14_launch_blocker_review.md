# Stage 14 — Launch Blocker Source Review

**Stage 14: IMPLEMENTED — VERIFICATION PENDING**

Baseline supplied by the developer: branch `ceylon-travel-mvp`, checkpoint `1c392fc Finalize Stage 13 launch integration`, CI GREEN. These are supplied baseline facts, not independently checked Git/CI results. Stage 13 runtime/manual verification remains deferred. No Stage 14 verification pass is claimed.

This review used source-file reads and edits only. No shell commands, application/test execution, Flutter commands, npm, Firebase CLI, gcloud, Git, builds, deployments, emulator, Android device or browser were run. Dependencies, lockfiles, indexes, Storage rules, backend Functions and timing/commercial rules are unchanged.

## Launch-critical paths reviewed

| Journey | Source findings |
| --- | --- |
| New Tourist and Driver registration | Existing Auth account creation and create-only draft profile path remain; retry reuses the created UID and missing-profile login resumes registration. Required identity/evidence/agreement submission and backend review remain separate. Initial account-type choice is constrained by rules; it is not a client upgrade or activation privilege. |
| Admin application review | Operation worker uses live Auth primary-admin claims and disabled state, current revision and immutable submission/evidence checks. Support-only staff cannot approve. Tourist approval activates Tourist access; Driver approval leaves payment/membership requirements outstanding. |
| Payment/membership and upgraded accounts | Existing quote, proof, review, numbering and activation path reused by new/upgraded drivers. Approval alone does not grant operational access. Stored pre-cutoff LKR 3,500 founding_lifetime quote remains authoritative after #100; new post-cutoff quote is LKR 5,000 registration plus LKR 10,000 annual renewal. No client fee calculation, number assignment or counter change. |
| Startup/login/logout | Firebase initialization precedes runApp. Splash resolves authenticated server profile with a bounded read and safe fallback; explicit login uses the same role/status destination helper. Stage 13 legacy-driver status routing and Logout remain. Suspended/inactive or pending profiles do not pass operational routing. Firebase-disabled login has an error path; live revocation behavior still needs device verification. |
| Tourist/Driver dashboards and open feed | Existing creator/open/current-assignment queries retained. Open trips sort first, newest creation first, with deterministic ID ties; lifecycle trips follow; completed/cancelled are excluded from active cards. Feed listener ownership fixed below. |
| Create Trip/Hire | Pickup/drop, passenger minima, future schedule and vehicle choice checked; rules enforce text/count bounds. Saving guard prevents duplicate taps; write failure is shown. Driver creator remains postOrigin=partner and driverId remains the creator compatibility field. Reference generated on new post. No map or fare logic added. |
| Bid submission | Existing operational helper plus driverCanBid, required price/vehicle description/number/duration, current open state, creator exclusion and cancelled-driver exclusion remain. Fixed UID bid document plus create-only rules rejects duplicates and ownership forgery. Rules independently validate state at commit. |
| Bid list/acceptance/assigned visibility | Creator-only atomic parent plus winning-bid transaction retained. acceptedDriverId identifies the performing driver; driverId is not repurposed. Losing bids are effectively closed by parent status while retained as submitted for supported reopen reuse. Current assignment queries exclude unrelated accepted trips. Bid listener ownership fixed below. |
| Cancellation/reopen | Creator cancellation is terminal; accepted-driver cancellation clears assignment, reopens the same post, cancels only that bid and excludes that driver. Other bids/history retained. Required reasons, reciprocal writes and server-time two-hour penalty decision remain. Cancellation after start is intentionally outside this workflow. |
| Private chat/manual location | Existing creator/current-driver routing, transactional send IDs and assignmentDriverId binding retained. Rules gap on reopened-trip history fixed below. Creator retains historical assignments; replacement driver cannot read old assignment messages. Manual one-shot location lookup, permission/timeouts and external Maps remain; no tracking added. |
| Start/end/completion | Existing role/state validation and server timestamp anchors retained: 180-second start and 1800-second end deadlines. Trusted backend automation remains authoritative. Completion and both parties' counters share a transaction; repeated transitions fail state checks or backend no-op. Lifecycle stale view handling fixed below. |
| Rating/written review | Completed trip and opposite participant required; fixed direction record, transaction and create-only rules prevent self/duplicate rating. Both sides submit stars plus required written comment. Existing public projection allowlist excludes private contact/identity/evidence. |
| Tourist-to-Driver upgrade | Existing same-UID draft, pending review, correction/rejection/resubmission and trusted approval flow reviewed. Identity ownership, revisions and private evidence checks remain. Approved account enters existing payment/membership path. |
| Admin operations and notifications | Primary/support privileges remain separate and claim-based. Existing workflow push uses generic identifiers/bodies, live audience validation and dedupe; evidence uses authenticated Storage bytes, not public download URLs. No notification system or admin feature added. |

## Blockers found and source fixes

1. **Dashboard feed resubscription failure.** DriverHomeScreen stored a single-subscription merged feed and placed its StreamBuilder inside lazily mounted ListView children. Scrolling the feed child out and back can dispose/recreate the listener against the same stream, producing `Bad state: Stream has already been listened to`. Tourist dashboard and creator bids had the same listener-lifetime risk. StreamBuilders now own the scrolling content, so scrolling cannot detach the subscriptions. Creator bids also remain subscribed when the parent trip temporarily shows an error. Query definitions, merge algorithm and dashboard layout are unchanged; no broadcast conversion or extra Firestore listener was added.
2. **Legacy driver operational bypass.** applicationOperational and approvedAccountProfile returned early/short-circuited driver checks when registrationStatus was absent. Stage 13 guarded startup, but direct operational service/rule paths remained permissive. Missing legacy registrationStatus is still compatible; drivers now always need the existing trusted identity, payment, membership/expiry and active account requirements. Legacy Tourists retain their existing behavior. Authorized admin reads and owner application/payment/support access are not tied to this operational gate.
3. **Former driver could read chat while the trip was reopened.** canReadAssignmentMessage used general parent-trip read access, which includes open posts, plus message assignment ownership. A cancelling driver could therefore read their former messages while the parent was open. Driver message reads now require current chat-participant status and the current acceptedDriverId as well as message assignmentDriverId. Creator history access remains intact.
4. **Lifecycle access errors retained stale private content/actions.** The screen previously displayed its last trip beneath an access-error banner. It now clears trip, accepted-bid and rating state on listener failure/participant loss, rejects callbacks from replaced subscriptions and catches synchronous signed-out subscription errors. Existing retry/back navigation remains; no lifecycle business transition or deadline was changed.

### Old Driver Dashboard stream issue assessment

An obvious current source cause remains at the supplied checkpoint; it was not treated as already resolved. The fix keeps the one existing subscription attached to the screen rather than a scrollable child. The historical report after a successful hire write was not reproduced here. Weekend verification must reproduce scrolling to Create Hire Post, saving, returning and scrolling the feed repeatedly, and confirm no duplicate listeners or missing feed updates.

## Files changed

Created:

- docs/stage_14_launch_blocker_review.md
- test/stage_14_launch_blocker_test.dart

Modified:

- lib/screens/driver/driver_home_screen.dart
- lib/screens/tourist/tourist_home_screen.dart
- lib/screens/tourist/tourist_bid_list_screen.dart
- lib/screens/trip/lifecycle_trip_screen.dart
- lib/core/models/registration_application.dart
- firestore.rules
- rules-tests/lifecycle.test.mjs
- test/stage_10_services_test.dart
- test/trip_cancellation_service_test.dart

The two existing service-test files only gain trusted eligibility fields in valid legacy-driver fixtures. Existing behavior assertions remain. Optional stream/service injection in the changed screens supports focused tests and does not change production data sources.

## Test source — not run

- Stage 14 Flutter tests cover operational legacy eligibility; one dashboard subscription through repeated scroll and post-route return, continued updates and disposal; bid subscription retention across parent errors; lifecycle stale-view clearing and signed-out entry.
- Existing lifecycle rules suite now tests incomplete legacy driver denial, valid legacy driver allowance, identity/payment/membership/suspension/expiry denial, and former/replacement-driver message get/query denial on reopen/reassignment with preserved creator history.
- Existing lifecycle, rating, chat, cancellation, Stage 13 and activation test sources were inspected; only tests needed for the changes above were added/adjusted. In-memory Flutter service fixtures are not a substitute for the rules emulator suite.

## Outstanding launch requirements and risks

- **Production Android signing remains outstanding in source.** android/app/build.gradle.kts explicitly signs release with the debug signing configuration. The developer must supply the intended protected release/upload signing setup before production distribution. No credentials or signing configuration were invented or changed.
- **Stage 14 checks and runtime verification remain pending.** Baseline green CI is not evidence that these edits pass. In particular, verify Firestore rule expression limits and query authorization with the complete existing suite; deploy the reviewed Firestore rule changes only after success.
- Confirm existing Firebase configuration, email/password provider, HMAC secret, counters, indexes, lifecycle task queues/service-account permissions and prior Stage 13 deployment are ready. Source review cannot establish deployed state. Verify the merged Android release manifest includes INTERNET and the declared notification/location permissions; the app's main manifest does not explicitly declare INTERNET, so dependency merging must not be assumed without verification.
- Current trusted automation intentionally no-ops for some newly ineligible/suspended participants. Trips paused by account intervention require operator review and the existing trusted recovery/requeue procedure; no new bypass or deadline behavior was introduced.
- Invalid historical data can require trusted repair; no migration, blanket default activation or counter repair was attempted. Ineligible legacy drivers will now lose operational access until existing activation requirements are actually met.

All identified code defects listed above have scoped source fixes. These outstanding release requirements must be resolved before declaring launch ready. No claim of exhaustive runtime correctness is made.

## Non-blockers deferred

- Friendlier client-side upper-bound feedback for unusually long trip text or large counts: server rules already reject invalid writes safely. No validation/rules expansion in this stage.
- Cosmetic placeholder notification button, display-name/branding polish and larger layout improvements.
- Feed/history pagination and scale tuning beyond the initial MVP; no query-architecture rewrite.
- Existing at-most-once FCM attempt limitations and token-bootstrap dependency; notifications are not the source of workflow truth.
- Phone-number recovery, profile pictures, OTP, email change, referrals, hotels, travel planner/map, continuous GPS tracking, in-app calling, phone masking, notification preferences, analytics, account deletion, large UI redesign and iOS production release. None implemented.

## Deferred weekend verification checklist

### CLI — developer runs later

- [ ] `flutter analyze`
- [ ] `flutter test test/stage_14_launch_blocker_test.dart test/stage_10_services_test.dart test/trip_cancellation_service_test.dart test/stage_10_cleanup_test.dart test/stage_11d_registration_attention_test.dart`
- [ ] `flutter test` (full suite, including Stage 13 and notification regressions).
- [ ] Firestore rules suite, required because firestore.rules changed: `npm --prefix rules-tests test`, using the existing local demo-project Firestore emulator setup in rules-tests/README.md. Inspect emulator logs for expression-limit failures as documented there.
- [ ] Functions build/tests if backend source is subsequently touched. No Stage 14 Function source changed; retain any outstanding Stage 13 backend verification.
- [ ] Storage rules tests if Storage rules are subsequently touched. Stage 14 leaves Storage rules unchanged; retain outstanding Stage 13 evidence verification.
- [ ] `git diff --check`
- [ ] Review the final diff, configure production signing and verify merged Android release permissions before release packaging.
- [ ] After successful tests, deploy the actual Firestore rule changes and confirm required existing indexes/Functions/task configuration. No deployment was performed here.

### Android runtime — after tests and required deployment

- [ ] Tourist registration/login, including retry after profile-write failure and missing-profile resume.
- [ ] Driver registration; primary-admin application review; correction/rejection/resubmission; support-only/revoked-admin denial.
- [ ] Driver quote/payment verification/membership activation; approval alone cannot operate; founding quote entitlement remains authoritative across #100.
- [ ] Tourist trip post and Driver partner hire post; verify creator metadata/reference and safe write-failure handling.
- [ ] Repeated dashboard scrolling, Create Trip/Hire navigation/save/return, live update and Retry: no already-listened error, duplicate listener or lost data.
- [ ] Open/unaccepted feed first/newest; accepted/current assignments visible only in intended feeds; completed/cancelled absent from active feed.
- [ ] Valid driver bid; duplicate, own-post, expired/ineligible/suspended and excluded-driver attempts rejected.
- [ ] Creator accepts one bid atomically; other bids effectively close; acceptedDriverId points to performer, not partner creator.
- [ ] Private chat and manual location share/external Maps. Exercise denied location permission and timeout.
- [ ] Creator cancellation closes permanently with reason; accepted-driver cancellation reopens same post, preserves reusable bids and excludes cancelling driver; two-hour penalty boundary preserved.
- [ ] After reopen/reassignment, old driver cannot read/query/write chat; replacement sees only its assignment; creator retains history.
- [ ] Start request/creator confirmation and trusted three-minute fallback; end request/confirmation and trusted thirty-minute fallback; duplicate/stale/wrong-actor actions denied.
- [ ] Completion appears in history; counters update once; both participants submit stars and written reviews once.
- [ ] Lifecycle screen clears stale content on permission loss; signed-out/missing document has a safe error/back path.
- [ ] Tourist-to-Driver upgrade, approval, payment/member activation and operational access only after eligibility.
- [ ] Logout/login, suspended/inactive/expired and legacy-driver routing, notification taps and account switching.
- [ ] Android small-screen/keyboard checks for forms, bids, chat, lifecycle and admin review.

Do not mark Stage 14 VERIFIED until the deferred checks and outstanding release requirements are resolved.
