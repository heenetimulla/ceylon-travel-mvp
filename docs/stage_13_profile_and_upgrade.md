# Stage 13 — Profile and account settings

## Stage 13A: Profile / Account Settings foundation

| Work | Status |
| --- | --- |
| Development | IMPLEMENTED — source changes; not yet verified |
| Flutter analyze | PENDING |
| Flutter tests | PENDING |
| Firestore rules tests | PENDING |
| Browser QA | PENDING |
| Android emulator QA | PENDING |
| Physical-device QA | PENDING |
| Firebase rules deployment | PENDING |

No commands, tests, builds, deployments, Git operations, browser or emulator operations were executed for this implementation. Dependencies and lockfiles are unchanged. The rules test script includes the new profile suite; the script was not run.

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

`rules-tests/profile_settings.test.mjs` covers owner-only safe edits, private reads, recent authentication, invalid/deleted values, protected field changes (including admin claims), and immutable workflow records. It uses the existing local-only rules emulator test infrastructure and is included in its test script. All test execution is pending.

Manual verification still required:

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

NOT IMPLEMENTED. Future work must use the existing application/evidence and trusted identity uniqueness architecture. No client account-type change or upgrade request is added in 13A.

## Stage 13C: Admin review / activation integration

NOT IMPLEMENTED. Future upgrade review must preserve custom claims, registration review, payment quote entitlements and membership activation requirements. No additional admin action or activation shortcut is added in 13A.
