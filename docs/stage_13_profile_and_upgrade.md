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

**IMPLEMENTED — VERIFICATION PENDING.** This stage implements the request, submission, correction and review-record foundation. Final approval/account-type transition is explicitly reserved for Stage 13C. A production operator cannot complete an upgrade to Driver with this stage alone.

| Verification after latest changes | Status |
| --- | --- |
| Flutter analyze, focused tests, full tests | PENDING |
| Functions build and tests | PENDING |
| Firestore rules tests | PENDING |
| Storage rules tests | PENDING |
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

Upgrade **Approve** is intentionally absent; even an admin operation attempting it is rejected by the worker as `upgrade-approval-unavailable`. There was no safe existing Tourist → Driver transition to reuse. `approved` is understood by the model/UI as a future handoff state, not generated by Stage 13B. Stage 13C must implement the trusted transition, driver workflow record and appropriate pending-payment/account state atomically. This boundary cannot be bypassed from Flutter.

No quote, payment, entitlement, registration number, membership or bidding change occurs in Stage 13B. Stage 11D remains authoritative: a valid pre-cutoff LKR 3,500 quote locks founding lifetime membership, new post-cutoff quotes are LKR 5,000 with LKR 10,000 annual renewal; no LKR 1,500 top-up, per-trip commission, second counter or client tier calculation is introduced. After the future trusted transition, identity/payment/membership/account checks must all pass before operational driving.

Upgrade audit actions use `driver_upgrade_*`, distinct from new-registration notification actions. Existing Stage 12 notification behavior is unchanged. A dedicated upgrade reviewer queue/notification and completion notification are reserved for Stage 13C; for now reviews are reachable through **Users & Drivers → account detail**.

### Security and deployment implications

Firestore permits only narrowly shaped owner upgrade operation requests at the current revision. Application heads, revisions, identity claims, review/audit fields and current upgrade summaries remain worker-managed. Direct writes to privileged user fields are still denied; Stage 13A's safe profile allowlist and recent-auth phone rule are unchanged. Another user and supportAdmin-only staff cannot read private application/evidence records or review upgrades. Admin authorization remains `admin: true`, never an account type.

Storage rules extend the existing registration-evidence upload predicate to active/approved Tourists with a server-created editable upgrade (`draft`, `correction_required`, `rejected`). This permits their DL/selfie uploads at the upcoming revision. Existing JPEG/type/metadata/dimension/size limits remain. Owner/admin get access is retained; listing, overwriting, deletion, other-user access and support-only review remain denied. Pending/approved states cannot upload replacements, including to the next revision. Metadata is re-read server-side before a new uploaded reference is accepted.

Deploy the updated existing `processRegistrationApplication` Function and Firestore/Storage rules after verification. It uses the existing `DRIVER_IDENTITY_HMAC_KEY`, `DRIVER_ADMIN_REGION` and `DRIVER_ADMIN_SERVICE_ACCOUNT`; do not rotate the HMAC key, reset counters or backfill old agreements. No new Function export, index, dependency, lockfile or secret is needed. Coordinate the client/worker/rule release: old clients submitting agreement 1.0 will need the updated app after the new rules/worker require 1.1.

### Source tests added/extended — not executed

- `test/registration_application_test.dart`: upgraded form and same-UID operations, required inputs/photos/agreement, correction/resubmission, historic v1.0 views, private admin review and no premature activation.
- `test/stage_13_profile_test.dart`: eligible Tourist entry, Driver exclusion and existing-state status instead of duplicate entry; keeps verified Stage 13A checks.
- `functions/test/registration_application.test.ts`: real worker logic with transactional fake; same UID, duplicate/concurrent draft/DL handling, current-state and revision guards, NIC reuse/other-UID denial, required fields/evidence, forbidden payloads, immutable history, legacy handling, v1.0 preservation and Stage 13C approval boundary.
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

After automated verification and reviewed deployment, manually exercise approved and legacy Tourists, fresh DL/selfie capture, persisted draft/pending status, private admin review, correction/rejection and resubmission. Confirm old revisions/agreements and Tourist access remain intact, phone change still requires Stage 13A re-authentication, no new Auth user appears, driver bidding remains unavailable, and existing Stage 10/11/12 flows regress cleanly. Browser/device QA and deployment remain pending; final upgrade activation cannot be live-tested until Stage 13C exists.

## Stage 13C: Admin review / activation integration

**PENDING — NOT IMPLEMENTED.** Reserved work:

1. Trusted final approval/account-type transition for an upgrade, preserving UID/history and validating the current submitted revision, HMAC ownership, agreement and private evidence (including explicitly referenced original NIC evidence). Atomically establish the driver verification workflow and pending payment/membership state without giving operational access early. Add reviewer queue/notification and completion workflow using the existing architecture.
2. Manual phone-number recovery for users unable to access the old number: recovery request, identity proof/evidence, primary-admin review, trusted phone change and immutable audit containing old/new number snapshots, actor, timestamp and support/recovery reference. Notify after completion. Recovery must not modify identity status, account type, membership or payment state.
3. Optional profile picture upload remains future work.
4. Phone OTP remains deferred.

No manual recovery, profile upload, phone OTP, email-change flow or additional privileged transition was implemented in Stage 13B.
