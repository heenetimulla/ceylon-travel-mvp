# Stage 13 — Profile and account settings

## Stage 13A: Profile / Account Settings foundation

| Work | Status |
| --- | --- |
| Development | COMPLETE |
| Flutter analyze | PASS — user-verified Stage 13A checkpoint |
| Focused Stage 13 profile tests | PASS — 14/14 |
| Full Flutter tests | PASS — 335/335 |
| Firestore rules tests | PASS — 87/87 |
| Git diff check | PASS — user reported clean |
| Git checkpoint | `93846f9 Add secure profile and account settings` — committed/pushed |
| Manual browser/device QA | DEFERRED |
| Stage 13 rules deployment | PENDING — no deployment confirmation supplied |

These Stage 13A results were supplied by the user; they are not verification of the later Stage 13B changes. No commands, tests, builds, deployments, Git operations, browser or emulator operations were executed during Stage 13B development. Dependencies and lockfiles are unchanged.

### Entry and display

Account & Support now includes **Profile & Account Settings**, available to authenticated tourists and drivers, including pending applicants through their existing Account & Support entry. An admin using a tourist account uses this same screen; admin tools and custom-claim authorization remain separate.

The screen displays initials, full name, phone, Firebase Auth sign-in email, account type, registration status and account status. Driver-only read-only details include registration number, identity/payment status, membership plan/status/expiry, vehicle type/number and operating area. Missing legacy fields display a safe unavailable/legacy label. No evidence, NIC/DL, document URLs, payment records or administrative notes are fetched from private workflow collections or displayed here. Email is read from Auth, not an independently editable Firestore value.

Existing shared page headers, responsive page padding, cards and theme are reused. Loading, retry, inline form validation, saving progress, error messages and success feedback are provided. Account & Support reloads its summary on return from settings.

### Explicit edit boundary

`ProfileService` exposes typed `updateDetails(fullName, city)` and `changePhone(phoneNumber, password)` methods. There is no arbitrary update-map entry point. `FirestoreProfileStore` writes only:

- Personal details: `fullName`, `city`, server `updatedAt`.
- Phone: `phoneNumber`, server `updatedAt`.

Full name is required and trimmed, up to 120 characters. City is optional, trimmed, up to 100 characters. Phone is required and trimmed; a basic phone-format check permits digits and common separators with an optional leading `+`. This validates formatting, not ownership of a phone number.

Vehicle/operating-area editing is intentionally excluded: these are submitted driver application information and no existing safe standalone owner-edit path was found. Avatar/photo editing is not included.

UID, email, account type, account/registration/identity/payment/membership statuses, membership plan/entitlement/expiry, registration numbers, application revision, submitted timestamp, admin/support claims, ratings/counters/metrics, verification/evidence and payment records are not editable through this service or the new rules path. The UI presents current status values without treating them as access grants.

### Phone change and authentication

The confirmation dialog requests a new phone number and the current email/password sign-in password. It explicitly confirms replacement of the application's contact number. Every save re-authenticates using the existing `AuthService` and Firebase `EmailAuthProvider`, then forces `getIdTokenResult(true)` so Firestore receives the refreshed trusted `auth_time`.

Rules independently require `auth_time` within the last five minutes for a changed phone number. A missing, stale or future timestamp is denied. The client does not write auth timestamps. Fresh-login sessions also satisfy the rule; Firestore cannot distinguish recent sign-in from re-authentication, while this UI always requires a password confirmation.

Wrong-password and recent-login failures prevent the write. Cancel makes no change. Firestore failures remain visible in the dialog. The password controller is cleared after each attempt and disposed when the dialog closes; passwords are not logged or persisted. Non-password Auth providers receive an unsupported-provider message instead of an unsafe fallback.

Only the app profile contact field changes. Firebase Auth phone identity is not modified. SMS OTP/phone ownership verification is deferred, and the UI says so; this feature must not be described as OTP-verified phone ownership. Existing submitted contact/evidence/payment/application snapshots are not rewritten.

The service binds to the opening UID, rejects stale results, and invalidates on logout/account switch even if the original UID later returns. The screen hides the old profile and closes its edit dialog after a session change. Writes already accepted by Firestore cannot be undone by later logout; rules remain the final owner boundary.

### Data responsibilities and rules

- `users/{uid}` remains authoritative for current account/profile state.
- `registration_applications/{uid}` and submitted revisions remain the application/review record with historical profile/contact snapshots.
- `driver_verifications/{uid}` remains the private driver administration workflow.

Changing current display/contact fields does not amend or resubmit an application. The existing permitted application correction workflow remains unchanged, including its backend-managed profile updates. If a correction is being submitted concurrently, that workflow and a settings save can update the same current profile fields; immutable submitted revisions still retain their original values.

`validSelfProfileUpdate` is a narrow owner-only diff allowlist, validates changed values and server `updatedAt`, and checks recent authentication for phone changes. Profile-shaped writes route to this validator exclusively, so mixing privileged fields with profile edits is rejected. Other updates retain the existing `validProfileEvent` rules for Stage 10 reciprocal completion/rating events. No lifecycle, registration, membership, payment, claims, token, public-profile projection, Storage or backend rules were redesigned. Admin claims grant no extra client profile-write permission.

The existing trusted public-profile projection continues to project its existing allowlist (including updated display name). Contact details and workflow evidence are not added to that projection. No new index, Function, secret or Storage configuration is required. Deploy the reviewed Firestore rules before expecting settings writes to succeed in a live project.

### Test source and manual verification

`test/stage_13_profile_test.dart` covers the typed service boundary, owner reads, Auth email, password/reauth failures, successful phone-only update, stale sessions, validation, missing legacy data, tourist/driver display, narrow/wide layouts, inline failure/cancel handling and load/retry/logout behavior. Its service tests use controlled sessions and stores, not live Firebase.

`rules-tests/profile_settings.test.mjs` covers owner-only safe edits, private reads, recent authentication, invalid/deleted values, protected field changes (including admin claims), and immutable workflow records. It uses the existing local-only rules emulator test infrastructure and is included in its test script. Stage 13A execution passed as reported above; regression execution after Stage 13B is pending.

Retained regression and deferred manual QA checklist (the automated Stage 13A baseline has passed):

1. Run Flutter analysis/tests and the complete Firestore rules suite, including existing Stage 10/12 regression suites, against the local emulator. Verify the new phone regex/recent-auth rules and unchanged lifecycle/metric behavior.
2. Review/deploy only the Firestore rule change after successful verification. No deployment was performed here.
3. Open settings as tourist, driver, legacy user, pending applicant and admin-with-tourist-account. Verify email matches Auth, current status displays correctly, driver fields remain read-only and no private evidence appears.
4. Save name/city, reopen settings and Account & Support, and verify persistence. Check the existing public name projection updates safely when applicable.
5. Verify blank/invalid phone and blank/wrong password show specific messages with no write. Confirm cancellation, stale auth and Firestore/network failure handling.
6. Confirm correct password changes only `phoneNumber` and server `updatedAt`; Auth email/phone identity, application history, payment records and all trusted fields remain unchanged. Verify fresh auth-time is available after re-authentication on web and Android.
7. Attempt forbidden edits and another user's profile writes in rules tests. Confirm fresh auth/admin claims do not bypass the protected-field boundary.
8. Switch/logout while loading or re-authenticating; ensure old profile/dialog contents disappear and no stale post-reauth save occurs.
9. Check narrow screens, wide browser layout, Android emulator and physical device, including keyboard/dialog scrolling and slow/offline connections. These QA passes remain pending.

## Stage 13B: Tourist → Driver/Partner upgrade request

**COMPLETE / VERIFIED** at checkpoint `f923a04`, as reported by the operator. Stage 13B implements the request, submission, correction and review-record foundation. Its original final-approval boundary is now completed by Stage 13C-1 below; verification of the new changes remains pending.

| Verification after latest changes | Status |
| --- | --- |
| Flutter analyze, focused tests, full tests (Stage 13B baseline) | PASS; 44/44 focused, 352/352 full |
| Functions build and tests (Stage 13B baseline) | PASS; 133/133 |
| Firestore rules tests (Stage 13B baseline) | PASS; 92/92 |
| Storage rules tests (Stage 13B baseline) | PASS; 3/3 |
| Git diff checks | PENDING |
| Browser, Android emulator, physical-device QA | DEFERRED / PENDING |
| Functions, Firestore and Storage rules deployment | PENDING |

### Same account and trusted operation architecture

Profile & Account Settings offers **Become a Driver / Partner** to an approved/operational Tourist with no existing upgrade. Existing upgrade states show **View driver upgrade** instead. The existing `RegistrationApplicationScreen`, `RegistrationApplicationPanel`, operation service and worker are reused; no second registration system, Auth user or `users` document is created.

Two owner operations use the existing `users/{uid}/application_operations/{operationId}` queue:

- `start_driver_upgrade`: atomically creates a draft in the same `registration_applications/{uid}` review record, with `purpose: driver_upgrade`, `targetAccountType: driver`, and a trusted original NIC revision pointer where available. Duplicate active flows are rejected. Draft creation records immutable audit events but is not itself a submitted revision.
- `submit_driver_upgrade`: checks owner identity, current Tourist eligibility, expected revision, current agreement, required driver fields and private evidence; reserves identity claims transactionally; creates the next immutable submission and audit event; returns the upgrade to `pending_review`.

Existing ordinary registration submissions now carry `purpose: registration`. Historical submissions without a purpose remain readable. The trusted worker chooses the purpose; applicants cannot set it or forge source revision pointers.

`users/{uid}` remains the current operational source of truth. New server-only summaries are `driverUpgradeStatus` and `driverUpgradeSubmittedAt`. `applicationRevision` continues the same monotonic submission sequence. For example: Tourist submission 1 → upgrade draft (still revision 1) → upgrade submission 2 → corrected upgrade submission 3. New photos belong to the upcoming revision (`applicationRevision + 1`).

Tourist `accountType`, registration approval, account status, identity status, profile/contact fields, payment/membership fields, metrics and original `applicationSubmittedAt` are preserved during the upgrade request and correction/rejection flow. Tourist access remains subject to the existing account checks; no driver capabilities are granted. Original trip, rating, support, identity, submission and audit history stays under the same UID. The current application head changes purpose, while previous submitted revisions and review history remain immutable.

Draft creation persists state and the trusted identity-source pointer. Form text and selected, not-yet-submitted photo references are not autosaved; leaving/reloading before submission requires entering/selecting them again. A corrected submission pre-fills previous non-sensitive driver details, requires licence re-entry and fresh revision-scoped DL/selfie uploads, and records fresh agreement acceptance. No old acceptance or evidence object is overwritten.

### Required data, identity and private evidence

The upgrade reuses current name, email, phone and city server-side. It accepts only these driver profile fields: `vehicleType`, `vehicleNumber`, `vehicleDetails` (make/model/details), `operatingArea`, `availableAreas`. All are required. Contact edits must use Stage 13A, including its phone re-authentication; upgrade payloads cannot bypass that flow.

Default vehicle choices are `Any`, `TukTuk`, `Small Car`, `Sedan Car`, `Van - Highroof`, `Van - Flatroof`, `SUV`, `Bus`. This is informational/default data only. Bid vehicle selection and bidding rules are unchanged.

The backend reuses a reviewed Tourist NIC from its immutable original submission when available. Its registry ownership must still belong to the same UID. The new submission records the original NIC evidence metadata with `reusedFromApplicationRevision`; the Storage object path and original revision are not changed or silently copied. A verified NIC cannot be replaced through this upgrade payload; discrepancies require support. Legacy accounts without an approved identity source must supply NIC number and NIC evidence as well.

Every upgrade requires a Driving Licence number, a new licence image and a new identity-verification selfie. Same-UID HMAC registry ownership is accepted; another UID's NIC or DL is rejected without disclosing account details. The existing normalization, keyed HMAC namespace, secret fingerprint check and transaction-level claims are reused. Registry documents remain server-only. Old reserved identity claims are not automatically released on correction/rejection, matching the existing conservative identity policy.

`DriverEvidenceService` and image preparation are unchanged: JPEG/PNG input, local JPEG normalization, metadata removal, document long edge 2000px / 2 MiB, selfie long edge 1600px / 1.5 MiB, quality 85 then 80 fallback. Mobile selfie remains camera-only; web/desktop uses the existing recent-photo selection fallback. Selfie is review evidence, not biometric authentication. The user previews, confirms readability and explicitly uploads before submission. New references use randomized `registration_evidence/{uid}/{nextRevision}/{kind}/{random}.jpg` paths. No public download URLs are created.

### Agreement 1.1

`lib/core/models/registration_application.dart` centralizes the current version, planned operator name and content. `registrationGuidelinesV1` retains the exact v1.0 text. Version 1.1 adds non-commission/platform role, no direct transportation operation, participant verification/responsibility, misuse/privacy/security terms, and liability wording qualified by **“except to the extent liability cannot legally be excluded.”** Private information is not intentionally sold or improperly disclosed; necessary service/permission/legal disclosures are described separately.

The operator name is centralized as `registrationOperatorName = 'VerTech Solutions'`. The text explicitly identifies it as the planned, not-yet-formally-registered operator name and invents no company registration or incorporated status. It is not represented as a lawyer-reviewed final contract. Any future material wording change must receive a new agreement version rather than silently altering accepted 1.1 terms.

All new registrations, upgrades and resubmissions require explicit v1.1 checkbox acceptance. Firestore operation rules and the worker agree on version `1.1`; the worker writes the acceptance timestamp using the same server transform as the immutable submitted revision. Existing 1.0 acceptances are not migrated or rewritten. A previously submitted 1.0 registration remains reviewable by its originally accepted version; a new submission cannot use 1.0.

### Review boundary and payment handoff

Primary admins can open the existing secure account detail/application panel, including for legacy Tourists with an upgrade. It clearly identifies the upgrade purpose, displays private identity/evidence only in the review context, and permits **Request correction** or **Reject** on the current pending revision with a required applicant-visible reason. History records actor, action, reason, timestamp, revision and operation ID.

At the Stage 13B checkpoint, upgrade approval was intentionally unavailable. Stage 13C-1 below now handles the trusted transition through the same `approve` operation. No client account-type write is permitted.

No quote, payment, entitlement, registration number, membership or bidding change occurs in Stage 13B. Stage 11D remains authoritative: a valid pre-cutoff LKR 3,500 quote locks founding lifetime membership, new post-cutoff quotes are LKR 5,000 with LKR 10,000 annual renewal; no LKR 1,500 top-up, per-trip commission, second counter or client tier calculation is introduced. After the future trusted transition, identity/payment/membership/account checks must all pass before operational driving.

Upgrade audit actions use `driver_upgrade_*`, distinct from new-registration notification actions. Stage 13B preserved existing Stage 12 behavior and provided reviews through **Users & Drivers → account detail**. Stage 13C-2 below adds these events to the existing queue/notification architecture.

### Security and deployment implications

Firestore permits only narrowly shaped owner upgrade operation requests at the current revision. Application heads, revisions, identity claims, review/audit fields and current upgrade summaries remain worker-managed. Direct writes to privileged user fields are still denied; Stage 13A's safe profile allowlist and recent-auth phone rule are unchanged. Another user and supportAdmin-only staff cannot read private application/evidence records or review upgrades. Admin authorization remains `admin: true`, never an account type.

Storage rules extend the existing registration-evidence upload predicate to active/approved Tourists with a server-created editable upgrade (`draft`, `correction_required`, `rejected`). This permits their DL/selfie uploads at the upcoming revision. Existing JPEG/type/metadata/dimension/size limits remain. Owner/admin get access is retained; listing, overwriting, deletion, other-user access and support-only review remain denied. Pending/approved states cannot upload replacements, including to the next revision. Metadata is re-read server-side before a new uploaded reference is accepted.

Deploy the updated existing `processRegistrationApplication` Function and Firestore/Storage rules after verification. It uses the existing `DRIVER_IDENTITY_HMAC_KEY`, `DRIVER_ADMIN_REGION` and `DRIVER_ADMIN_SERVICE_ACCOUNT`; do not rotate the HMAC key, reset counters or backfill old agreements. No new Function export, index, dependency, lockfile or secret is needed. Coordinate the client/worker/rule release: old clients submitting agreement 1.0 will need the updated app after the new rules/worker require 1.1.

### Source tests added/extended — not executed

- `test/registration_application_test.dart`: upgraded form and same-UID operations, required inputs/photos/agreement, correction/resubmission, historic v1.0 views, private admin review and no premature activation.
- `test/stage_13_profile_test.dart`: eligible Tourist entry, Driver exclusion and existing-state status instead of duplicate entry; keeps verified Stage 13A checks.
- `functions/test/registration_application.test.ts`: real worker logic with transactional fake; same UID, duplicate/concurrent draft/DL handling, current-state and revision guards, NIC reuse/other-UID denial, required fields/evidence, forbidden payloads, immutable history, legacy handling and v1.0 preservation. Stage 13C-1 extends the original approval-boundary tests with trusted approval and denied invalid transitions.
- `rules-tests/driver_upgrade.test.mjs`: owner-only commands, protected fields, version/revision checks, immutable private application history and denied self-approval.
- `rules-tests/driver_upgrade_storage.test.mjs`: owner/current-revision uploads, private admin review, denied unrelated/support access, no list/overwrite/delete, metadata/type/dimension/size constraints and locked-state uploads.

### Exact manual verification commands (Windows CMD)

These are instructions for the operator; none were run during development. Use existing installed dependencies. From the repository root:

```bat
flutter analyze
flutter test test/registration_application_test.dart test/stage_13_profile_test.dart
flutter test
npm --prefix functions run build
npm --prefix functions test
git diff --check
git diff --stat
git status --short
```

The Functions test script includes its build. For a focused worker test after a successful build, optionally use:

```bat
node --test functions/lib/test/registration_application.test.js
```

Firestore suite in two CMD windows, with Firebase CLI and its Java emulator prerequisites already installed. Window 1, repository root:

```bat
firebase emulators:start --only firestore --project demo-ceylon-upgrade-rules
```

Window 2, repository root (use the emulator's displayed port if it differs from 8080):

```bat
set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
npm --prefix rules-tests test
```

After stopping that emulator, run the separate Storage suite with both emulators available. Window 1, repository root:

```bat
firebase emulators:start --only firestore,storage --project demo-ceylon-upgrade-storage
```

Window 2, repository root (adjust to displayed ports if necessary):

```bat
set FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
set FIREBASE_STORAGE_EMULATOR_HOST=127.0.0.1:9199
npm --prefix rules-tests run test:upgrade-storage
```

The tests require loopback endpoints and use only `demo-*` projects; they clear their test data. The Storage suite uses the matching Firestore emulator for Storage rules' profile lookups. The existing Firestore suites use their own demo project namespaces. Emulator project-mismatch warnings from those independent suites do not authorize production access. No production project ID belongs in these verification commands.

After automated verification and reviewed deployment, manually exercise approved and legacy Tourists, fresh DL/selfie capture, persisted draft/pending status, private admin review, correction/rejection and resubmission. Confirm old revisions/agreements and Tourist access during review remain intact, phone change still requires Stage 13A re-authentication, no new Auth user appears, driver bidding remains unavailable until activation, and existing Stage 10/11/12 flows regress cleanly. Browser/device QA and deployment of Stage 13C-1 remain pending.

## Stage 13C-1: Trusted Upgrade Approval Transition

**COMPLETE / VERIFIED**, as reported by the operator. Checkpoint: `b2feef9 Add trusted driver upgrade approval`. Overall Stage 13 is not complete. This statement does not claim deployment or verification of later Stage 13C-2 changes.

The existing `processRegistrationApplication` Function processes the existing primary-admin `approve` operation; there is no new operation, Function export or client privilege. The authenticated, non-disabled actor must have `admin: true`. Support-only staff and applicants cannot approve. An eligible active Tourist with a current pending upgrade is required. Account/head/revision consistency is checked transactionally, including equality with the immutable submitted revision, upgrade purpose/target, Agreement 1.1 and matching trusted acceptance/submission timestamps.

Approval revalidates the existing HMAC fingerprint and NIC/DL registry ownership. Reused NIC data must match the original immutable Tourist submission and its evidence reference. All three evidence objects are re-read through the existing Storage metadata validator, including the original NIC revision where reused; generation and all stored metadata must match. Required vehicle/default-vehicle details and operating areas are validated again. Missing, altered, conflicting or inconsistent data fails closed; existing unexpected driver workflow/commercial state requires operator review.

One Firestore transaction updates the same `users/{uid}` to `accountType: driver`, `driverUpgradeStatus: approved`, `registrationStatus: approved`, `identityVerificationStatus: verified`, `accountStatus: pending_approval`, `paymentStatus: pending`, and `membershipStatus: pending`. Only driver-specific profile fields are copied; current name, phone, email, ratings, metrics and all existing history are preserved. Approval equals identity approval in the existing Stage 11D application architecture, so no duplicate identity decision is required. The private `driver_verifications/{uid}` workflow and its immutable `submissions/application_{revision}` snapshot are created and `driverAdminRevision` advances. The submitted account type in snapshots remains historical; only `users/{uid}` is authoritative for current operational state.

No Auth account, quote, payment record, membership plan, entitlement, registration number or counter is created or assigned by this approval. The existing driver payment request, manual payment verification and membership activation remain mandatory. Existing founding quote/cutoff and annual entitlement logic are unchanged. Account activation remains part of the existing membership activation flow. Existing driver eligibility denies bidding and other operational access until all requirements pass; Tourist operational access ends at the trusted account-type transition.

The application head records the review decision. Immutable application history and `users/{uid}/admin_history` record `driver_upgrade_approved`, target UID, admin UID, revision, purpose, previous/resulting account type, resulting account status, server timestamp and operation ID, with no raw identity data. Submitted revisions and previous agreements are not edited. Retries of a completed operation no-op; concurrent or new-ID repeated approvals fail current-state checks after the first commit and cannot create a second transition/audit.

The admin panel exposes **Approve Driver Upgrade** with confirmation explaining the same-account transition and remaining payment/membership requirements. The applicant's existing profile upgrade status and application/payment panel show approval without claiming operational activation. Existing secure routing reads current account state. Upgrade queue/notification integration was deferred at this checkpoint and is implemented separately in Stage 13C-2 below.

No Firestore or Storage rules, dependencies, indexes, secrets, lifecycle logic or commercial rules change. Deploy the updated existing `processRegistrationApplication` Function after manual verification and release the updated Flutter review UI. Retain the existing HMAC secret and Function configuration.

Test source updates cover primary-admin approval, same UID/profile/history preservation, rejected unauthorized actors, stale/malformed revisions and agreement, required driver fields/evidence, registry conflicts, Storage metadata changes, concurrent/replayed approval and payment-required activation. Flutter coverage checks confirmation/cancellation, current-revision operation submission, and non-operational approved drivers. Rules coverage checks admin command creation while denying direct account-type/approval/audit writes by every client, including admins.

Stage 13C-1 verification is complete as reported by the operator. Retain its regression checklist for later changes: approved/legacy Tourist upgrades, rejected stale approvals, preserved original history, payment quote/slip/verification, final membership activation and only then driver bidding. Also verify disabled/revoked admins cannot submit a new approval and support-only accounts cannot review. Do not infer a production deployment from this verification status.

## Stage 13C-2: Admin Queue + Notification Integration

**IMPLEMENTED — VERIFICATION PENDING.** No commands, tests, builds, deployments or device/browser QA were run during this stage. Overall Stage 13 remains incomplete.

### Existing admin queue

The existing Pending Registrations screen now includes accounts with either `registrationStatus` or `driverUpgradeStatus` in `pending_review`, `correction_required` or `rejected`. Correction Required covers either workflow. All, Tourists and Drivers retain their existing current-account-type semantics. New **Driver Upgrades** includes pending/correction/rejected and approved upgrade records, so promotion to `accountType: driver` does not erase their origin. Drafts remain outside the review queue. Approved records leave All/review queues and enter the unchanged Payment & Activation query when payment or membership needs attention; the upgrade filter also retains completed approved upgrades for reference.

Queries still order by document ID and paginate 30 accounts with a document-ID cursor. Firestore OR filters deduplicate accounts; the existing aggregate attention count now includes upgrades. Payment/activation counts and conditions are unchanged. Each page reads at most 30 individual application heads to get the existing trusted `purpose`; only the safe purpose is retained. Application listing remains denied. Current status/revision/timestamps remain from `users/{uid}`, using `driverUpgradeSubmittedAt` for upgrades and `applicationSubmittedAt` for new registrations. A missing historical purpose falls back to the existing server-managed upgrade summary. No new source of operational truth or migration is introduced.

Cards identify **New Tourist registration**, **New Driver / Partner registration**, or **Driver Upgrade**, with current account type, application state/revision, submission time and existing contact summary. NIC/DL, HMAC keys, reasons and evidence are not placed in card/search models. Rows open the existing protected detail. Upgrade detail explicitly identifies the original Tourist account, requested Driver / Partner role, purpose and current resulting account type. Private evidence controls are unchanged.

One users composite index is added: `driverUpgradeStatus ASC, accountType ASC, __name__ ASC`, for the role-filtered upgrade branches. Existing registration and Payment & Activation composites are retained. Non-role upgrade queries use the existing automatic single-field indexing and document-ID order. Deploy the reviewed index and verify actual queries before live use. No entire-users scan or client-side pagination over a collection is used.

### Existing workflow notifications

The existing **notifyRegistrationReviewEvent** create trigger on immutable application history now recognizes trusted `driver_upgrade_*` actions. No Function export, token store, delivery implementation or notification channel is added. **syncNotificationStaffTokens**, shared token pagination/cleanup, `workflow_push_delivery` markers and delivery revalidation are reused unchanged.

| Trusted event | Push type | Audience |
| --- | --- | --- |
| Submission/resubmission → pending_review | driver_upgrade_submitted | Primary admins only, excluding applicant/actor |
| Correction requested | driver_upgrade_correction_required | Applicant only |
| Rejected | driver_upgrade_rejected | Applicant only |
| Approved | driver_upgrade_approved | Applicant only |

Before delivery and before each device-page send, the worker rechecks user existence, same owner, purpose/target/source account type, application head/current revision, upgrade state, matching event/action/timestamp and review actor. Reviewed decisions require a current primary-admin actor. Staff candidates are revalidated through live Firebase Auth claims and disabled state; supportAdmin-only and ordinary users cannot receive upgrade review pushes. No client profile role field is trusted. New revisions have new immutable event IDs; retries retain the same marker and do not repeat a logical attempt.

Bodies are fixed and generic. Approval says: “Your Driver/Partner upgrade was approved. Complete the remaining payment and membership steps to activate driver access.” Payload contains only `type` and `accountUid`. No identity numbers, phone, evidence paths, bank data, amounts, reasons or admin notes are copied. No application writes are performed by delivery. System/bookkeeping events are not new application history events, so no loop is introduced.

The existing **at-most-once attempt** limitation remains: a crash/network failure or empty staff index after claiming a marker can lose delivery; FCM delivery is not exactly-once guaranteed. Temporary failures retain valid tokens; only permanently invalid tokens are removed safely. Reviewer candidates still require the existing login/token-refresh bootstrap. No historical event replay/backfill is included.

### Tap routing, status and payment handoff

The single Stage 12 parser/session/navigation host recognizes the four new types. Every asynchronous server read/claim refresh keeps existing UID/session-epoch checks. Reviewer taps require primary admin claims before and after loading, then open the existing gated account review screen only while the upgrade remains pending. Owner taps verify UID, purpose, head/revision and authoritative upgrade status, then open the existing correction/status screen or current driver payment/status flow. Already-operational drivers reach their dashboard only through the existing eligibility helpers, including annual expiry and account suspension. Stale or unauthorized results return through the existing safe home fallback.

The Firebase notification reader now uses the existing bounded document-ID users query for non-owner admin profile reads: direct profile gets are owner-only under current rules. Private application heads still use authorized individual gets. No security rule is broadened.

Profile/application status now distinguishes approved-but-awaiting-activation from driver membership active using trusted current eligibility, never `accountType` alone. Payment submission/verification/rejection and membership activation continue through **notifyDriverOperationCompleted** and existing types. No duplicate payment/identity/activation push is synthesized by upgrade approval. Quote issuance, founding entitlement/cutoff, commercial pricing, registration numbering and operational gates remain untouched.

### Test source and manual verification

Added/extended queue model/widget and rules-query fixtures for new registrations, upgrades, correction, pagination, safe summaries and approved payment handoff; notification tests for each event/audience, resubmission, stale/malformed records, revocation, sender suppression, dedupe, multiple devices, privacy, token cleanup and FCM failure isolation; resolver/profile tests for upgrade parsing/routing, claims, session switches, current operational state and logout. Existing Stage 12 test coverage is retained.

All latest verification is **PENDING**: Flutter analyze; focused/full Flutter tests; Functions build/tests; Firestore rules regression; index deployment; updated Function deployment; Android emulator/physical device and browser QA. Existing manual commands above remain applicable. Additional focused Flutter source can be verified manually with:

```bat
flutter test test/stage_11d_registration_attention_test.dart test/fcm_workflow_notifications_test.dart test/stage_13_profile_test.dart test/registration_application_test.dart
```

After automated checks, deploy the new composite index and the updated existing `notifyRegistrationReviewEvent` Function, then release the client update. No new dependency, secret, permission, Firestore rule or Storage rule is required. Verify first submit, correction/resubmit, reject, approve, reviewer claim revocation, account switching, payment handoff and final membership activation using separate applicant/admin devices. Confirm old and upgraded driver payment notifications remain single events and no private content appears on lock screens. Stage 12A–D regressions remain part of the manual verification pass.

## Stage 13C-3: Manual Phone Recovery

**PENDING — NOT IMPLEMENTED.** Reserved work:

1. Manual phone-number recovery for users unable to access the old number: recovery request, identity proof/evidence, primary-admin review, trusted phone change and immutable audit containing old/new number snapshots, actor, timestamp and support/recovery reference. Notify after completion. Recovery must not modify identity status, account type, membership or payment state.
2. Optional profile picture upload remains future work.
3. Phone OTP remains deferred.

No manual recovery, profile upload, phone OTP, email-change flow or additional privileged transition was implemented in Stage 13B.
