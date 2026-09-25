# Stage 11A, 11B and 11C manual verification

All checks are for the operator. Codex did not execute tests, analyzer, builds, Firebase commands, npm, package installation/upgrades or Git commands. Dependency declarations for evidence are source edits only.

## Setup

Admin provisioning policy: no public admin registration, no user/driver request-admin-access flow, and no admin request queue. Only trusted Admin SDK tooling provisions initial claims. Later staff/admin creation must use an already-authorized trusted super-admin/admin backend operation; that functionality is not implemented yet. Flutter must never set privileged claims.

1. Review the narrow Firestore rule changes and the aggregate/list privilege limitation in stage_11_implementation.md.
2. Prepare normal tourist and driver accounts, a supportAdmin-only account, and a primary admin account. Use test accounts without real customer private data for permission checks.
3. Create the initial Auth login separately through trusted Firebase administration. After manually compiling the Functions project, use the local operator script from that directory: `node lib/src/set_admin_claims.js grant <UID>`. Set GOOGLE_CLOUD_PROJECT explicitly and configure trusted ADC first. Grant sets both admin and supportAdmin true while preserving unrelated claims. Revoke syntax is `node lib/src/set_admin_claims.js revoke <UID>` and removes both flags only. Do not put credentials in Flutter/source control and do not create any public self-promotion endpoint. This script is not a deployed function or application endpoint.
4. Keep the admin account's existing tourist/driver accountType and profile. Sign out/sign in to obtain a new ID token. Deploy the revised Firestore rules manually. No Functions deployment, package installation or additional composite index is required for 11A.
5. Run the new focused Dart tests, analyzer and your normal regression suite manually when ready.

## Operator claims tool checks

- Use a disposable existing Auth account in the intended project, with unrelated test claims. Grant and confirm both admin/supportAdmin are true and all unrelated claims remain unchanged. Repeat grant and check the same result.
- Revoke and confirm both admin/supportAdmin keys are absent and all unrelated claims remain. Repeat revoke; no user should be deleted or created.
- Verify missing UID, extra arguments, unsupported action, missing project, unavailable ADC, insufficient permissions and nonexistent UID fail clearly without raw error objects, tokens, credentials or private profile output.
- Confirm success output contains only the safe operation message and UID. Verify no users, trip, support or other Firestore documents were written.
- Sign out/sign in or force-refresh the ID token after each change. Do not treat claim removal as immediate revocation of already-issued tokens.
- Keep per-UID operator updates serialized: the Auth API replaces the claims object and offers no compare-and-swap for concurrent claim writers.
- Confirm `set_admin_claims.ts` is absent from the deployed Functions entry-point exports. There must be no public registration/request-admin UI, request queue, endpoint or client claim setter.
- Run `functions/test/set_admin_claims.test.ts` through the existing manual Functions test workflow when ready. Its tests exercise pure helpers only; no Firebase network access is required.

## Authorization and privacy

| Actor/action | Expected |
| --- | --- |
| Signed out opens admin screen directly | Sign-in message; no operational queries |
| Normal authenticated user opens Account | Admin option absent |
| Normal user opens admin screen directly | Access denied; no stats/support preview |
| supportAdmin only | Admin option absent; existing support staff permissions remain |
| admin is string "true", false or absent | Denied |
| admin boolean true | Account entry visible; dashboard accessible |
| Token read failure | Safe error/retry on direct screen; no data |
| Sign out/change account while overview loads | Old overview removed; no prior-user result displayed |
| Normal user lists arbitrary users or gets another private user | Denied |
| Normal user lists all support requests | Denied; their existing own-request query remains allowed |
| Primary admin counts users/trips/support and loads latest 5 support parents | Allowed |
| Primary admin lists complete parent documents | Allowed by necessary aggregation list grant; acknowledge this trusted-admin privilege |
| Primary admin alone reads support message threads or sends staff replies/status changes | No new grant; still requires existing owner/supportAdmin authorization |
| Primary admin alone reads other participants' trip messages/GPS | Denied by unchanged assignment/participant rules |
| Normal user writes admin/supportAdmin or accountType=admin into users/public profile | Rejected; never affects trusted custom claims |
| Admin deletes users/trips/support/ratings, or arbitrarily edits profiles | No new permissions; existing denials remain |

Check actual server reads, not just hidden buttons. Rule tests must exercise queries as well as direct document reads. No emulator/rules integration tests were added or run by Codex. Keep the existing Stage 10 checks for Driver B being unable to read Driver A's retained text/GPS.

## Overview data

1. Compare totals with known test documents. Total Users counts users documents, including inactive profiles; driver/tourist cards filter the original accountType values exactly. Auth accounts without profiles are not included.
2. Create/reuse known trips in open, accepted, start_requested, in_progress, end_requested, completed and cancelled states. Active must include exactly the four specified active states. Open and completed must remain separate. Total Trips includes cancelled as well.
3. Create support records in open, in_review, resolved and closed. Open Support Requests must count only open, not in_review.
4. With more than five support requests, confirm the latest five by createdAt appear. Verify reference, category, status, user ID, created/last-message dates and the original submitted contact-number snapshot. Changing a profile phone must not change historical support contacts.
5. With no support requests, verify an explicit empty state. Valid empty collection counts should display zero; network/permission errors must not display invented zero counts.
6. Disconnect/block a query: verify a safe unavailable/retry screen without raw backend diagnostics or cached private preview. Restore access and retry.
7. Refresh after data changes; check new totals/preview. There is no automatic polling or atomic cross-query snapshot guarantee.
8. Verify the 360px mobile layout and a 1400px browser layout, long identifiers, text scaling, scrollability, readable contact/date fields and centered desktop content. Use existing app theme. Confirm back navigation still works.
9. Remove the admin claim through the trusted operator process and refresh/sign in again. The menu/dashboard should disappear on the updated token. Account for already-issued token expiry; claim removal is not instant global revocation.

## Regression checks

Verify login/registration, ordinary Account & Support links, dashboard identity/order, tourist and partner trip creation, bidding/acceptance, cancellation/reopen/exclusion, three-minute auto-start, thirty-minute auto-complete, completed statistics, mutual ratings/reviews/public profiles, support creation/contact snapshots/two-way messaging, private assignment-specific text/GPS chat, map launching and Sri Lanka trip references. No Stage 10 backend, schema, service or timing behavior should change.

Stage 11B adds only Users & Drivers browsing and read-only details. Stage 11C adds the support inbox below. No deletion, account moderation, verification actions, role upgrades or reporting controls should appear.

## Stage 11B: pending operator verification

All checks below remain pending. Codex made coding/documentation changes only and did not execute commands or perform UI testing. No new rules, dependencies, Functions or index-file changes are part of Stage 11B.

### Local checks to run manually

From the intended `feature/stage-11` checkout, review the changed files and run:

```text
flutter analyze
flutter test test/stage_11_admin_test.dart test/stage_11b_admin_users_test.dart
flutter test
flutter build web
```

Use the project's normal build for any additional target platforms you support. These are suggested operator commands, not commands executed by Codex. Confirm branch/base and review diffs using your own workflow; no Git checks or branch changes were performed by Codex. Existing Stage 11A tests must continue passing unchanged.

### Server authorization and data access

1. Confirm the intended environment already has Stage 11A rules. Stage 11B makes no rule changes and requires no additional admin write/delete grant.
2. As signed out, ordinary tourist, ordinary driver, supportAdmin-only, and an account with absent/false/string-valued admin claim, try both list and detail routes directly. Expect denial/sign-in/error as appropriate, no private account rows and no data-source reads from the gated UI. Confirm the dashboard entry remains hidden for non-admins.
3. With a refreshed boolean `admin: true` token, open Account → Admin Dashboard → Users & Drivers → View account. Verify both primary-admin-only and admin+supportAdmin combinations can browse. No profile field or stored accountType should need to change.
4. Exercise real server `users` list queries: All, exact tourist/driver filters, ascending document ID, limit 50 and startAfter cursor. Confirm index availability in the target environment. Exercise the detail list query with document ID equality and limit 1. These should be allowed for admin and denied for ordinary/supportAdmin-only users. Direct document get of another user's profile remains denied, including for admin unless that admin owns it.
5. Confirm no reads of user subcollections, driver verification evidence, Storage images, messages, GPS or unrelated collections are triggered by list/detail navigation. Confirm no profile/claim updates or deletes are attempted. Existing metric-event write permissions and ordinary owner reads must remain unchanged.
6. Sign out/change account/revoke admin through the trusted operator process and refresh the token while list, pagination or detail reads are pending and while either route is already showing data. Private content must disappear; late results must not reappear. Test both routes on the navigation stack and navigating back. Existing issued-token expiry caveats still apply.

### Account data and paging

1. Prepare at least 51 safe test profiles across tourist and driver, plus a legacy profile missing createdAt and optional fields. Use controlled document IDs. Verify ascending ID ordering, a 50-account first page, subsequent page cursor, no duplicate cards, completion message and refresh. Also check an exact 50-record filtered set: the final empty page should finish cleanly.
2. Check All includes every profile, including unknown/missing accountType; Tourist/User and Driver match only exact stored `tourist`/`driver`. Unknown accounts must never be treated as admins. Switching filters resets pagination, preserves search and ignores an older response arriving late.
3. Search by mixed-case full name, email substring and phone digits with/without punctuation. Confirm search is explicitly limited to loaded accounts in the selected filter. Search for an account on page two: no false global-empty claim, Load more remains available, and the match appears after loading its page. Clear search and confirm the loaded rows return without another query.
4. Compare card data with the stored profile: name, account type, phone, status, completed/cancelled trips, cancellation percentage, average rating/count and optional verification. Missing values must say Not available/Unknown, while stored zeroes stay zero. Verify nested `verification.status` fallback for existing drivers.
5. Open details and verify name, canonical document UID, type, email, phone, city, status, local created/updated dates, all requested metrics, verification, and photo path/status. No image request should occur; Path provided does not mean verified or downloadable. Test missing/null/malformed fields, long strings and an account removed between list and detail reads.
6. Simulate slow/offline/permission-failing first-page, next-page and detail reads. Expect explicit loading, safe error text and retry without raw SDK messages. Next-page retry must reuse the same cursor without duplication. Refresh must clear previous data while loading; detail refresh must fetch fresh server data. Server-source reads must not silently fall back to cache.
7. Confirm an empty collection/filter and no search matches have distinct explanations, with a way to change filters/search. Auth-only users without private profile documents are outside this browser; do not compare the profile total to the Auth console total without accounting for that.
8. Insert/edit records while browsing, then refresh. Confirm documented non-atomic paging behavior: IDs inserted before a cursor can require refresh. Search must not launch an unbounded server scan or one query per keystroke.

### Layout, read-only scope and regressions

1. Inspect 360px mobile and 1400px desktop widths, long names/emails/UIDs/photo paths, large text scaling, keyboard search, scrolling, focus/semantics, filter controls and back navigation. There should be no overflow and field values should remain readable/selectable on details.
2. Inspect all list/detail controls: only search, filters, pagination, refresh, retry, access recheck, view and navigation are expected. Confirm absence of delete user, reset password, change accountType, grant admin, suspend account, edit profile and approve/reject driver actions. All destructive/account-change operations are deferred, potentially to Stage 11D.
3. Repeat the Stage 11A overview checks above: all eight statistics, loading/error/refresh states, latest five support requests, contact snapshot and access gating. Repeat the normal app regression checks; no support, trip, rating, chat or user-registration behavior should change.

## Stage 11C: pending manual/live verification

All checks below are pending. Codex performed coding/documentation changes only, with no commands, test runs, analyzer, builds, deployments, emulator or manual UI sessions. Stage 11B live UI was reported verified by the user. The intended branch/base are `feature/stage-11` / `bd89f59`; no Git commands or merge were performed.

### Operator verification commands and setup

Run manually from the intended checkout:

```text
flutter analyze
flutter test test/stage_11_admin_test.dart test/stage_11b_admin_users_test.dart test/stage_11c_admin_support_test.dart
flutter test
flutter build web
```

Use the normal build workflow for any other supported targets. Review the narrow support audit rules and new `support_requests(status ASC, createdAt DESC)` index; deploy them through the approved manual Firebase workflow and wait for index readiness before live testing. No Functions deployment or dependency upgrade is required. Retain the existing messages/assignment index. Confirm no unintended files or Stage 11A/11B behavior changed.

Use safe test data in the intended environment. Prepare an ordinary owner, a different ordinary account, a primary-admin-only account, a supportAdmin-only account and an account with both claims. Use the trusted operator process to provision the desired claims and refresh/sign in; never edit accountType or profile admin fields. Existing issued-token validity caveats apply.

### Authorization matrix (verify server operations, not only hidden UI)

| Actor | Expected Stage 11C behavior |
| --- | --- |
| Signed out, ordinary tourist/driver, false/string supportAdmin | No staff entry; inbox/detail denied; no staff operations |
| admin true only | Existing dashboard/users/parent preview access remains; staff inbox, other users' threads/history and staff writes denied |
| supportAdmin true only | Account staff entry, inbox, threads, reply and audited status change allowed; no primary-admin dashboard or Users & Drivers access |
| Both boolean claims | Dashboard Support & Complaints entry and all intended staff operations allowed |
| Request owner without staff claim | Existing own request/messages and user reply work; no staff-role reply, status change or status_history access |
| Different ordinary user | Another request/thread/history read or write denied |

1. Open both staff routes directly for every actor. Verify sign-in, denied and token-error states do not load private data. Confirm no profile field grants support access.
2. Sign out/change account/refresh revoked claims while inbox, detail, pagination or a write is pending. Content and drafts must disappear on gate disposal and late results must not reappear. A transaction already committed may remain committed; the client must not claim to roll it back. Test returning to a route underneath the active route.
3. Confirm primary-admin-only staff denial does not affect existing dashboard parent support preview or stats. The operator CLI's ordinary grant already supplies both claims; do not silently expand rules for a missing staff claim.

### Inbox, search and layout

1. Seed/reuse more than 50 requests covering all four stored states, including tied createdAt timestamps, general questions and trip complaints from both roles. Verify newest-created order, descending document-ID tie-breaker, 50-row pages, no duplicates and final completion. Check an exact 50-record filter requires a final empty read. Inspect actual server queries/index use.
2. Verify All, Open, In Progress (`in_review`), and Resolved / Closed (`resolved`, `closed`). No `in_progress` status should be stored. Change filter while a query is pending and ensure stale results cannot replace it.
3. Search loaded rows by SUP reference, CT reference, contact digits/formatted number, submitted name, category/subcategory and subject. Search must perform no query per keystroke and must not claim global completeness. A matching request on page two should appear after Load more even when page one has no matches.
4. Verify row identity, UID, submitted contact snapshot, optional trip reference, created/updated/last-message times. Change the owner's profile phone externally and confirm the submitted contact remains unchanged. No extra profile/email/private-data lookup should occur.
5. Check empty collection/filter, no search match, slow reads, offline/permission/index failures, safe errors, retry at the same page cursor and refresh. Refresh clears stale data; server reads must not fall back to cache. Requests missing createdAt are outside the existing schema and excluded by ordering; identify such records separately if they exist, without automatic migration.
6. Inspect 360px mobile and 1400px desktop widths, large text scaling, long references/names/phone numbers, keyboard search, focus, scrolling and hit-testable navigation buttons. Confirm the existing theme and rounded cards remain consistent. Returning from details should refresh the inbox.

### Full conversation and replies

1. Open a general request and a trip complaint. Verify original subject/message, generated acknowledgement, submitted name/role/UID/contact, optional human-readable trip reference and all available dates including year/local time. A general request must not need tripId/tripReference.
2. Use a thread with more than 50 messages, including identical timestamps. Load every page oldest-first; verify no missing/duplicate messages, author labels/UIDs, immutable text and timestamps. Test paging errors/retry and empty history. Staff Refresh picks up new customer replies; no live listener is promised in the admin UI.
3. Send a staff reply and inspect Firestore: exactly one new message with id, authenticated senderId, senderRole `admin`, trimmed text and server createdAt; parent changes only updatedAt/lastMessageAt/lastMessageId. Prior messages and original request/contact/category/trip/owner/reference fields must remain byte-for-byte unchanged.
4. Verify the customer thread receives the reply as Support team through its existing listener, then send a customer response and refresh staff view. No custom claims should appear in message text. No fake pending/success message should be appended locally.
5. Try blank/whitespace-only, 4000-character and 4001-character replies, double taps, offline failures and permission loss. Pending sends disable actions; failed sends retain the draft. Retry identical text on the same screen and confirm the same operation ID produces at most one message, including an already-committed/unconfirmed outcome. Reusing that ID with different actor/text/role must fail. Closing the screen loses the in-memory pending ID; refresh/check the thread before a new submission after ambiguous outcomes.
6. Close a request and confirm replies fail at both UI and rules. Explicitly reopen it to reply again. Resolved requests still accept replies as before. Confirm no automatic closure.
7. Directly attempt message update/delete, parent delete, changing sender identity/role, missing parent metadata updates, wrong timestamps, extra message fields and overwriting an existing message ID: all must fail under existing message rules. Ordinary owners may still send only `user` replies to their own non-closed requests.

### Status workflow and audit-rule negative checks

1. Exercise open → in_review → resolved → closed and an intentional reopening. Confirm only status/updatedAt/lastStatusEventId change on the parent, and exactly one new status_history document records id, real actorId, prior state, new state and server createdAt. Verify dates and staff UID appear in paged status history. Existing unaudited records must not receive invented history.
2. With two staff sessions, change a status in one session, then submit a different transition from stale state in the other. The transaction must reject it and instruct refresh; it must not silently overwrite the new state. Repeat the same completed operation ID and ensure no duplicate event or stale parent rewrite occurs.
3. Attempt a status-only update without an audit event, an event-only create without the parent update, an existing/reused event pointer, mismatched parent/event destination, incorrect previous status, same-status event, forged actor, client timestamp or unsupported state (`in_progress`, `suspended`, etc.). Every attempt must be denied. Verify actor and timestamp consistency under a real atomic batch/transaction.
4. Attempt to combine a status update with changes to userId, supportReference, original contactNumber, category/subCategory, tripId/tripReference, userName/userRole, original message/subject, createdAt or last-message metadata. All such combined writes must fail. An unrelated field cannot be added through the status path.
5. Attempt audit-event update/delete and parent/message delete as staff: denied. Attempt audit reads/writes as owner, unrelated user or primary-admin-only: denied. Ensure valid existing customer creates/replies still pass after a lastStatusEventId has been added to the parent.
6. Test any separately maintained older staff tool: direct status writes without a linked audit event are deliberately no longer allowed. Update such tools to the atomic schema before using the new rules; no unaudited fallback is permitted.
7. Verify history paging beyond 50 events, tied timestamps, safe retry and refresh. Parent/history/message loads are separately consistent; refresh after concurrent changes.

### Regression and scope

Repeat Stage 11A stats/recent support/authorization checks and Stage 11B navigation, search/filter, read-only details and pagination. Confirm normal Contact Us submissions, immutable contact snapshots, automatic acknowledgements and two-way customer threads still work. Repeat the existing trip, rating and private chat/GPS regression checks. No account suspension/approval/deletion, admin role management, message edits/deletes, automated penalties, notifications, daily reports or analytics controls should exist.

The new Dart tests use ordinary fakes and exact production payload builders. Live Firestore transaction idempotency, rule enforcement, concurrent changes and index readiness remain manual/integration checks; no emulator/rules execution was performed by Codex.

## Stage 11D — pending operator verification and deployment

All checks below are pending. Codex did not execute commands, analyzer/tests/builds, Firebase, Git, npm, emulator or manual UI checks. Earlier Stage 11A–C live verification is supplied by the user. Run checks manually on feature/stage-11; do not merge to ceylon-travel-mvp as part of this work.

### Setup and deployment order

1. Review new sources/rules and run `flutter analyze`, `flutter test test/stage_11d_driver_administration_test.dart`, the existing Stage 11A/B/C suites and the normal Flutter regression/build checks. In functions/, run the existing `npm test` and `npm run build` scripts manually. No dependency upgrade is required. Backend tests use a transaction contract fake, not an emulator.
2. Provision the dedicated DRIVER_ADMIN_SERVICE_ACCOUNT runtime identity. Grant only the Firestore/Auth/Secret Manager capabilities required by this worker (transaction reads/writes, Auth getUser and access to the bound secret); verify deployment/event delivery permissions through the existing Functions deployment process. Confirm DRIVER_ADMIN_REGION, default asia-southeast1, matches this project's conventions.
3. Configure DRIVER_IDENTITY_HMAC_KEY securely in Secret Manager with high-entropy random material of at least 32 UTF-8 bytes. Do not put a production secret in Flutter, source control, test fixtures or logs. Verify missing/short secrets fail safely. Preserve system_config/driver_identity_registry after first use. A changed secret must fail closed; rotation requires a planned trusted rehash/migration and is not implemented here.
4. Inspect existing official registrations before initializing system_config/driver_registration_counter.nextRegistrationNumber through a trusted operator. Use 1 and foundingOfferClosed false only for a fresh system; otherwise use the next unused official number and establish authoritative registry/cutoff consistency. Set foundingOfferClosed true once 100 successful activations have occurred, with foundingOfferClosedAt, foundingOfferClosedByRegistrationNumber 100 and the single closure event reconciled from authoritative history. Missing/inconsistent cutoff state must fail closed. Reconcile older quotes missing entitlement fields using their original server-issued terms and an audited trusted metadata migration; preserve founding entitlements and verified financial history. Never reset a production counter or delete uniqueness registries to fix a failed request.
5. Set up private evidence intake and staff access, retention procedures, receiving-bank instructions and a consistent unique bank-record reference convention. The identity form accepts NIC/licence numbers without document references; payment claims still use private slip references. Optional private identity photo uploads/review are now implemented by the evidence correction below; bank details and payment-slip uploads remain outside scope. Demonstrate that an owner/admin can locate and review the actual evidence securely without public document exposure.
6. In a non-production project first, manually deploy the new processDriverAdministration trigger, the changed public-profile projection and the reviewed Firestore rules. Confirm the durable request collection remains protected and event retries work before exposing submission UI. Coordinate production deployment of rules/app/worker and existing-driver approvals: new bidding and bid acceptance require completed Stage 11D fields. Existing drivers are not automatically grandfathered/migrated. No new index is required. The evidence correction below adds pinned Flutter dependencies requiring manual resolution.

### Access, rules and private data

1. Exercise signed-out, tourist, ordinary driver, unrelated owner, primary-admin-only, supportAdmin-only and combined claims. Only primary admin:true gets review/activation/account controls. Only the owner gets their submission controls. Support inbox powers remain exactly as Stage 11C.
2. Attempt raw direct writes as each client role to identity/review documents, payments, admin_history, config/counter, identity/payment/registration registries and the users high-level membership fields. All must be denied, including primary admin clients. Admins submit only operation requests. Existing allowed ordinary profile/metric behavior must remain unchanged.
3. Attempt operation creation with another actor, incorrect server timestamp, completed status, unsupported action, owner self-verification, wrong target, unexpected payload keys, negative revision and writes by a tourist. Rules/backend must reject them. Attempt operation updates/deletes and forged results: denied. Check Auth revocation/disabled status before processing a queued request prevents approval.
4. Attempt accountType, email, phoneNumber, fullName, uid, ratings/counts, completedTripsCount, cancellation fields and profilePhotoPath changes through every new action. They must remain unchanged. Attempt updates/deletes of audit/submission/payment history: denied. Confirm no delete/password/role/contact/profile/metric edit controls exist.
5. Verify only owner/primary admin can read full identity and payments; only primary admin can read admin_history. Unrelated users/supportAdmin must be denied. Inspect public_profiles and normal trip/support documents: no raw NIC/DL, evidence paths, payments or membership details may be projected. Identity label must prefer the new trusted status, including rejection over legacy verified data.

### Legacy identity flow and duplicate races

For NEW Tourist/Driver accounts use the final application checklist below, including required photos.

1. Open Driver Dashboard or Account → Driver verification & membership, enter NIC/licence numbers without document references; confirm pending status and immutable submission version. Verify missing/null/malformed older data safely displays without authorizing bidding. Required/invalid input must fail safely.
2. Manually review in Users & Drivers detail. Confirm verify/reject dialogs, optional reason, actual admin UID/review timestamps, matching high-level status, revision increment and exactly one immutable audit. Canceling must cause no operation. Driver cannot replace verified identity or set review fields.
3. Submit the same NIC on two accounts, the same licence on two accounts, and old/new NIC aliases (e.g. 901234567V and 199012304567). Repeat concurrently. Exactly one account may claim each identifier; a rejected operation must not partially claim the other identifier. Retry identical operation IDs and confirm no duplicate submissions/claims. Whitespace/case/hyphen normalization must work.
4. Confirm rejected/corrected identities do not release previous registry claims. Document an operational escalation for disputed claims; do not bypass uniqueness by deleting records. Test secret mismatch after initialization in a disposable project: identity submission and payment verification must fail safely.

### Payment and bank review

1. Request a reference as a driver. Confirm LKR 3,500/founding_lifetime before cutoff or LKR 5,000/standard_annual after closure, globally reserved CT-PAY reference and pending unsubmitted payment. Inspect quotedRegistrationFeeLkr, quotedMembershipPlan, quotedAnnualRenewalRequired, quotedAnnualRenewalFeeLkr, quotedAt and foundingOfferOpenAtQuote. A quote must not increment/reserve a driver registration number. A second pending request must fail.
2. Submit amount, YYYY-MM-DD payment date, transaction reference, depositor and private slip reference. Confirm the displayed expected/claimed amount, driver name/UID, reference and evidence match. Reject malformed dates/amounts safely. Submitted claims cannot be edited even by their owner; drivers cannot self-verify.
3. As primary admin, compare actual bank records and enter the canonical bank-record reference. Confirm verifiedAt/verifiedBy, immutable original fields, total credited once, audit and high-level payment status. Wrong claimed amount cannot verify or activate membership. Canceling the dialog has no effect.
4. Attempt a second verification/rejection of a verified payment, repeat the same operation, use concurrent reviewers and reuse the same canonical bank record for another account. No double credit or overwritten verified history is allowed. Rejection may be followed by a separate new quote/claim; reason and original rejected record must remain visible.
5. Issue a LKR 3,500 founding quote before closure, activate another eligible driver at #100, then verify and activate the earlier quote at #101 or later. It must require only the original LKR 3,500, remain founding_lifetime with no renewal/expiry, and preserve the payment record. Repeat with payment verified before closure. Reject and replace an earlier pending claim after closure: original terms and quotedAt must survive; no new annual entitlement may replace them.

### Membership, counter and concurrency

1. In isolated fixtures, activate #99 and confirm the offer remains open. Activate #100 and confirm cutoff state closes with server timestamp, registration number 100 and exactly one admin_notifications/founding_offer_closed event. A new user’s quote after this commit must be 5000/standard_annual/true/10000. Activate that quote and check first UTC anniversary expiry, including leap-day clamping. Activate a pre-cutoff quote at #101 or later and check 3500/founding_lifetime/false/null with membershipValidUntil null. Registration number and commercial entitlement are independent; lifetime membership may cover more than 100 accounts.
2. Verify activation before identity/payment approval, with wrong totals, missing private verification/payment, tourist target, missing/invalid counter or an already-used registry number fails without partial writes or counter advancement. The confirmation dialog must be required.
3. Activate two different eligible accounts simultaneously around #100/#101: distinct consecutive official numbers, one counter increment each, each account’s preserved quote entitlement and one audit each. Activate the same account simultaneously and replay with both the same/different operation IDs: no extra number, counter increment, credit or activation audit. The cutoff closes once and the fixed-ID event is created once. Race new quote issuance against activation #100: its committed transaction order must determine initial entitlement, and later activation must preserve it.
4. Submit from stale driverAdminRevision after another action. It must fail with refresh guidance. Retry a committed-but-unconfirmed operation; no duplicate side effects. Interrupt event delivery temporarily and restore it: queued request remains visible, no fake approval and eventual outcome is recorded atomically. A UI timeout is not proof of rollback. Refresh recent results before a new request.
5. Verify standard membership expires operationally at its anniversary; stored membershipStatus is not automatically changed by a scheduler. Renewal payment/extension automation is deferred. Founders never acquire a renewal fee/expiry through this stage. The membership payment applies to the account for many trips, with no quota/commission/per-trip fee.

### Account decisions, UI and regression

1. Exercise active/inactive/suspended with explicit confirmation and optional reason; cancel each dialog once. Reject invalid statuses. Verify only accountStatus/updatedAt/revision and the matching audit change; no automatic identity/payment/membership/ratings/cancellation changes.
2. Submit/accept bids for each incomplete requirement, inactive/suspended accounts, expired annual members and eligible lifetime/annual members. Client preflight and authoritative rules must agree; acceptance of an old bid rechecks eligibility. Confirm existing assigned-trip completion, trip history and support still work. No complaint/rating/cancellation causes automatic punishment.
3. At 360px and wide desktop widths, exercise driver owner portal, admin identity/payment/membership/account sections, long references, dates, pending/verified/rejected/missing states, dialogs, loading/error/retry, payment/history paging beyond 20 and operation-result display. Verify no overflow or obscured controls. Sign out/change account/dispose during pending reads: no stale private data should appear.
4. Repeat Stage 11A stats/recent support, Stage 11B search/filter/pagination/tourist read-only detail and Stage 11C support conversations/status history. Driver detail now intentionally includes confirmed administration controls; tourist detail does not. Confirm customer verification/trip/support flows remain intact.
5. Review immutable event contents against each successful action: previous/new values, real actorUid, reason, createdAt and operationId. Failed/no-op actions must not invent audit transitions. Verify payments and admin history page correctly with tied timestamps. Separate reads can briefly reflect different revisions; refresh must resolve them.

Pending limitations: live rule enforcement, Auth/event/IAM behavior, real Firestore concurrency, UI layouts and builds have not been verified here. Secure document intake/storage access, bank instructions, HMAC secret/runtime identity/counter setup and deployment remain operator work. No automated renewals, referrals, vouchers, external KYC/OCR, payment gateway, notifications, account deletion or role management are included.

### Quote entitlement correction — additional pending security/UI checks

- As owners, support-only staff and primary admin clients, attempt direct cutoff reopening, counter changes, quote fee/plan edits, activation and closure-event creation/update/delete. Deny all. Inject quotedRegistrationFeeLkr, quotedMembershipPlan, expectedAmountLkr or foundingOfferClosed through operation payloads; deny them. A post-cutoff claim for 3500 against a 5000 quote must fail verification.
- Get admin_notifications/founding_offer_closed as primary admin: permitted. Get as owner/support-only, list notifications, mark read, update or delete: denied. Confirm exactly one immutable event with the specified title/message, registrationNumber 100, createdAt and read false. The optional in-app dashboard banner remains pending; no push/email delivery exists.
- Confirm driver/admin payment cards display stored quote terms and wording no longer ties membership to eventual registration number. Run the focused Flutter test including the private `_panel` helper; confirm library_private_types_in_public_api is resolved. Re-run backend cutoff/concurrency/idempotency/quote-security tests and existing identity/payment/Stage 11A–C regressions manually.
- Deploy the corrected processDriverAdministration worker and narrow single-event read rule only after counter/legacy-quote reconciliation. No deployment, migration, tests or other commands were executed by Codex.

### Legacy number-only driver identity UI — pending verification

These checks apply ONLY to existing profiles without registrationStatus. New accounts must follow the final application checklist below.

1. Deploy the small processDriverAdministration compatibility change manually before testing against the live worker: document/selfie references may be absent, and authorized manual review accepts number-only submissions. No rules, HMAC secret, identity registry, membership or payment policy change is required. Codex did not deploy or run commands.
2. Sign in as a legacy driver without registrationStatus and reach the normal Driver Dashboard. Open its verification card and repeat through Account. Check inline NIC/licence inputs, blank/whitespace/overlong validation, trimmed old/new NIC formats and backend format-error messages. Tourists must see no driver entry or form. No document/slip/selfie placeholder should be required for identity.
3. Submit once and inspect the authenticated submit_identity operation: only the two number fields, original expectedRevision and real actor. Confirm private verification/submission records and registry claims are server-created, with null absent evidence paths. Await a confirmed result, then check pending status, masked values and absence of a normal resubmit control. Repeat with delayed/offline results: no optimistic success or accidental duplicate; refresh before another request.
4. As primary admin, view full numbers only in private account detail, manually verify or reject with reason, and check audit. After rejection, refresh as owner and submit corrected numbers; confirm revision checks, preserved old submission and retained uniqueness claims. A stale request must fail safely. Users cannot self-verify, and supportAdmin alone cannot review.
5. Check public profiles, normal account lists and trip/support surfaces contain no raw numbers. Owner status summaries must show only masked values; dedicated private entry/review may show full values. Confirm sign-out/disposal removes private forms.
6. Try bidding while ineligible: show the verification/membership guidance rather than raw permission errors. Recheck payment/membership/cutoff behavior, Stage 11A–C navigation and mobile/wide layouts. Run Flutter analyzer/tests and the backend suite manually; none were run here. Verify optional identity photo uploads using the checklist below.

### Private evidence uploads — all checks pending

The driver_evidence/number-only checks below describe the preserved legacy workflow. New accounts use registration_evidence with required role-specific photos and the next application revision; see the final checklist.

Codex did not run commands, tests, builds, emulators, dependency resolution or deployments. The following work belongs to the operator:

1. Resolve the newly pinned Flutter dependencies (image 4.5.4, file_selector 1.0.4, firebase_storage 13.4.5), inspect the resulting lockfile/plugin registration and avoid unrelated upgrades. Verify compatibility with the existing Firebase versions and firebase_core_web override. Run the Flutter analyzer, focused driver_evidence_test.dart and stage_11d_driver_administration_test.dart, Stage 11A–C regression tests, and the Functions build/test suite including driver_evidence.test.ts and driver_administration.test.ts. Then verify Android and web builds; check iOS separately if supported by the release. None has been verified here.
2. In a disposable/non-production environment, configure the private default Storage bucket shared by Flutter and Admin SDK. Review any existing live Storage rules before adopting this repository's default-deny rule file. Grant the worker narrowly scoped storage.objects.get and authorize the Storage rules service agent to read Firestore. Configure authenticated browser-download CORS for actual app origins if testing web. Coordinate the updated processDriverAdministration worker, Firestore evidence-payload validation and Storage rules deployments before exposing the UI. Do not deploy broad public read/write access or merge unrelated branches.
3. As an unsubmitted driver, open Driver verification & membership. Select separate JPEG/PNG NIC/licence/selfie photos. Check Preparing image..., optimized preview, zoom inspection, confirmation, replace/remove controls, upload progress and ready state at 360 px and wide widths. Upload must remain disabled until clarity is confirmed. Submission must remain disabled while photos are preparing/uploading or selected but not uploaded. Number-only submission still works. Cancel selection and replace/remove an existing selection without accidentally changing identity state.
4. Use large real camera images, portrait EXIF orientation, transparent PNG, fine-print documents and a selfie. Inspect the prepared image visually at zoom before upload. Verify output long edges <=2000 document / <=1600 selfie, JPEG quality policy 85 then 80 if needed, no EXIF/GPS/original filename, <=2,097,152 document bytes / <=1,572,864 selfie bytes. If fine text or face is unclear, do not confirm; choose/retake another photo. Check HEIC/HEIF, renamed archive/executable, PDF, animated PNG, corrupt/truncated files, inputs >20 MiB or >24 MP, tiny/narrow photos and output still over cap: friendly rejection and no original upload. Measure performance/memory on an actual lower-memory Android device and browser; web preparation is local but uses the UI thread.
5. Interrupt connectivity during upload, deny access, change driverAdminRevision through another operation, leave the page, sign out and change account. Confirm friendly errors, no optimistic submitted state, safe refresh/retry and no private image surviving its authorization-gated panel. Check stale uploads cannot become attached to a newer revision. An interrupted/replaced upload may remain a private orphan; it must not alter verification or registry data.
6. Inspect Storage and the submitted operation: only optimized JPEG bytes at driver_evidence/{own UID}/{expectedRevision}/{type}/{random32hex}.jpg, with matching five custom metadata fields; no original image/public download URL. Verify that the configured Firebase SDK's server-managed metadata does not conflict with the strict custom-metadata allowlist. Check bucket cache settings and token policy; the app must not generate or expose download-token URLs. Inspect current private verification and immutable submission history: server-read size/MIME/upload time/generation, dimensions, type/path/revision only; no binary/original filename. Retry an unchanged operation ID and verify nested evidence maps do not cause a false payload conflict or duplicate history.
7. Exercise raw Storage requests as signed-out, tourist, owner, another driver, support-only and primary admin. Only owner driver creates their own current-revision evidence. Deny other UID/revision, unsupported type, invalid filename, spoofed owner/revision metadata, missing/extra metadata, PNG/or arbitrary MIME at upload, zero/oversized bytes, and out-of-bounds dimensions. Deny overwrites/deletes/listing for every client role. Only owner and primary admin can get a known private evidence path; unrelated users/support-only cannot. Also attempt changing evidence maps on completed operations and directly writing verification/history: denied. MIME validation is not binary inspection; do not treat these rules as OCR/malware validation.
8. As primary admin open dedicated driver detail, view each photo privately, compare numbers/readability and verify or reject with a reason. Confirm support-only staff and ordinary users cannot fetch those objects. Rejected owner submits corrected numbers/new photos with the latest revision; old submission and its objects remain unchanged. Pending/verified owner does not get a normal replacement flow. Ensure no photo/path appears on public profiles, normal account lists, trip/support surfaces or analytics.
9. Recheck identity uniqueness/HMAC, expectedRevision conflicts, payment quotes/verifications, founding cutoff entitlements, activation, bidding guidance and Stage 11A–C behavior. No fee, membership, identity normalization, approval claim or automated punishment policy should change.
10. Define retention/reconciliation before production: unused uploads from cancel/replace/failure are private and immutable to clients. Only a trusted operator/job may remove confirmed orphans after checking pending operations and all retained submission versions. Do not use blanket expiry that removes historical evidence. Confirm bucket billing/quota/access policy with real volumes; this change minimizes individual image size but adds no upload-rate quota or generic cleanup infrastructure.


## Final registration applications — all verification pending

These are the CURRENT checks for new Tourist and Driver accounts. Earlier number-only intake checks are legacy-only. Codex did not run any commands or runtime verification.

1. Resolve dependencies manually with firebase_storage **13.4.5**, keeping firebase_core_web **3.10.0** override and unrelated Firebase declarations. Inspect the generated lockfile/plugin changes. Run analyzer, Flutter tests (registration_application_test.dart, widget_test.dart, driver evidence/admin and Stage 10/11A–C suites), Functions compilation/tests including registration_application.test.ts, and Android/web builds. iOS requires separate validation if shipped.
2. Review firebase.json and exports. Coordinate deployment of processRegistrationApplication, updated processDriverAdministration, lifecycle/public-profile Functions, firestore.rules and storage.rules before releasing the new client. Keep the existing HMAC secret, fingerprint, registries and registration counter; do not reset or rotate them. Confirm runtime secret binding, Firestore/Storage IAM, private bucket and browser CORS. No deployment/migration was performed here.
3. Create a Tourist: complete initial basics, observe draft/pending_approval, then NIC, required NIC photo/selfie and agreement 1.0. No licence/vehicle/payment controls. Missing number/photo/agreement must prevent submission. Review and submit: pending_review/pending_approval, revision 1, trusted agreementAcceptedAt and immutable private snapshot. Auth creation alone must not grant home/operational access. Sign out/in and resume; also test Auth created but profile creation interrupted.
4. Create a Driver through the same registration UI: additional licence photo/number, vehicle and operating area required. Test all three evidence cards, review, submission and pending routing. Approve application as admin: identity verified but account still pending_approval, unable to bid. Follow existing quote/payment/manual verification/membership activation; only then allow operations. Repeat preserved founding/standard and expiry/cutoff regression cases.
5. As pending, correction-required and rejected applicants, attempt UI and raw SDK trip posting, bidding, acceptance, lifecycle, operational chat and ratings. Deny at authoritative boundaries with friendly client guidance. Test backend automatic lifecycle transitions do not advance newly unapproved/inactive participants. Generic Contact Support, status, Account and logout must work. Approved active Tourist can operate; inactive and incompletely activated Driver cannot.
6. Submit duplicate NIC across Tourist/Driver, duplicate driver licence, normalized aliases and simultaneous applications. Exactly one claim succeeds, with no partial second claim; response must not disclose UID/name/contact of the holder. Legacy registered HMAC claims must also conflict. Check approval fails safely if trusted registry ownership/fingerprint is inconsistent. Do not delete claims to resolve conflicts; establish an operator review process. Reconcile known historical identities not previously collected before rollout.
7. Review both roles in Users & Drivers private detail as primary admin. Normal lists must have no raw NIC/DL. Test Approve, Reject and Request correction; reject/correction requires reason. Owner/supportAdmin-only/non-admin cannot review, self-approve or use legacy driver operations to bypass applications. Concurrent review/replayed operations must create only one transition/audit.
8. Reject/request correction, refresh as owner, inspect safe reason and additional-review warning. Correct permitted fields, re-enter identity, replace/re-upload required photos under next revision, accept agreement again and submit. Confirm revision increases, status returns pending_review/pending_approval, old claims/snapshot/photos/agreement/audits remain. Stale requests fail. Account type/email/ratings/cancellation/trip metrics are not editable. Both rejected and correction-required currently allow resubmission.
9. Open Application history, page beyond 20 with tied timestamps, and open earlier submitted revisions. Confirm correct private evidence and original agreement timestamp/version; review reasons and actor (admin view) persist. Failed confirmed operation can retry with a new ID; delayed/timeout operation remains uncertain until refreshed, without duplicate revision. Sign out/switch UID/remove admin access during pending loads and private previews: no stale authorized view remains.
10. Reuse image validation/compression checks above for BOTH roles: JPEG/PNG only, JPEG normalization, document 2000px/2 MiB, selfie 1600px/1.5 MiB, quality 85 then 80, orientation/EXIF removal, readability/progress/error states and low-memory Android/web performance. New paths use registration_evidence/ownUid/nextRevision/type/random.jpg. Owner upload only while editable; owner/admin known-path reads only. Deny unrelated owner, support-only, listing, overwrite/delete, wrong revision, extra/spoofed metadata, unsupported/oversized MIME and Tourist licence uploads. The worker must validate actual object metadata, and no original/public URL may appear.
11. Attempt client writes to approval/account state, identity registry, agreementAcceptedAt, current application, submitted history/audit, quote/counter/membership, arbitrary operation fields or operation results. Deny all, including primary admin direct privileged writes. Check initial profile email matches Auth and application revision/status cannot be forged.
12. Inspect public_profiles, trip/support surfaces and normal account lists for NIC/DL, document/selfie/payment paths, private notes and HMAC values: absent. Confirm new unapproved/inactive profiles are not projected. Private owner/admin details remain authorized. No migration of legacy data was performed.
13. At 360px and wide widths test keyboard/scrolling, dialogs, all states, errors/retry, navigation and history. Repeat Stage 10 lifecycle/chat/rating and Stage 11A statistics, 11B pagination/search, 11C support replies/status/audit. Validate live Firestore query indexes and real transaction contention; source fakes do not establish deployed rule correctness.
14. Before production, establish trusted orphan-upload cleanup/retention, guideline wording review, bank instructions and historical-identity reconciliation. These operational tasks, resolver/build results and all manual/live checks above remain incomplete. No automated cleanup, permanent rejection mode or historical identity migration was added.


## Attention queues, payment slip and camera correction — pending checks

No commands, tests or deployments were run for this correction. Earlier text-only proof instructions are superseded for NEW claims.

1. Resolve image_picker 1.2.1 without changing Firebase Storage 13.4.5 or core-web override 3.10.0; inspect generated lockfile/platform registration. Check Android minimum API 24 and iOS camera/photo-library descriptions. Run analyzer, Flutter tests and Functions tests/build manually, then Android/iOS/web builds as supported.
2. Deploy coordinated registration/driver Functions, Firestore rules, payment_evidence Storage rules and users composite indexes. Confirm worker Storage read IAM and index readiness. Do not reset HMAC/counter/registry or rewrite payment references.
3. Populate isolated pending_review/correction_required/rejected Tourist and Driver accounts, including legacy status active. Check Pending Registrations count/filters, bounded pagination >30, no raw NIC/DL, missing submitted dates, loading/error/retry, session revocation and stale filter responses. Rejected is follow-up eligible; drafts are not submitted-queue entries.
4. Review private identity numbers, role-specific photos, vehicle information, agreement and submitted time. Approve Tourist: ACTIVE and disappears after queue refresh. Approve Driver: pending payment/membership and account pending_approval; moves out of identity review into Payment Pending. Detail panels reload after the action.
5. Check Payment Pending badge counts exactly approved Drivers with paymentStatus pending. Its wider list also includes rejected-payment retries and membership activation; separate activation count is verified-payment/pending-membership. Payment-row navigation opens payment details first. Verify counts refresh on return and no existing dashboard/support entries or stats change.
6. As approved Driver, confirm explicit not-active-yet instructions. Direct navigation/posting/bidding remains blocked until all current users fields meet eligibility. Identity/payment/membership snapshots must not override users state. After verified payment, membership activation and active account, Check approval and continue opens Driver Dashboard. Check annual expiry still applies.
7. Before a slip is uploaded, Submit payment claim is disabled and no editable slip-path input exists. Camera/gallery selection, prepare, preview, readability confirmation and explicit Upload must work. Verify progress and uploaded state. Interrupt/fail/replace/remove: stale or unuploaded selection cannot submit. Confirm successful claim includes the exact private payment path.
8. Verify JPEG/PNG normalization, EXIF/GPS removal, quality 85/80, max 2000px/2 MiB, corrupt/unsupported/oversized rejection, no public URLs/original upload, and no binary/private filename in Firestore. Review server-read slipEvidence metadata. Tamper owner/payment/type/MIME/size/dimensions: backend must fail safely without accepting/crediting a claim.
9. Exercise raw Storage requests: owner current pending unsubmitted payment may create once; unrelated users/support-only cannot read/write, admin may get but not create. Owner can get their evidence. Deny list/overwrite/delete, other payment/UID, unapproved new Driver, noncurrent/final/submitted payment, spoofed metadata, PNG upload and oversized content.
10. Admin privately views slip, compares bank records and confirms Verify payment. SupportAdmin alone and owners cannot verify/reject/activate. Reject without a reason fails; valid rejection preserves prior proof/audit. Activate membership is hidden until verified payment and still requires identity/counter/quote checks. Payment verification and activation remain separate.
11. Generate multiple new references: match ^CTP[0-9]{6}[A-Z0-9]{6}$, length 15, no hyphen/space, separate payment ID. Replay an operation and race requests; no changed reference or duplicate registry assignment. Confirm existing CT-PAY references remain byte-for-byte unchanged through review. Pre-cutoff entitlements remain lifetime after cutoff; standard fee/annual rules remain intact.
12. Reconcile existing pending text-only claims before production: new verification rejects missing uploaded proof. Reject with reason and issue a replacement preserving quoted entitlement, then upload/submit. Do not mutate the old reference/claim. Existing verified payment history and activated accounts must remain unchanged.
13. On actual Android/iOS, selfie opens camera only, preferably front camera; cancel/denied permission does not open gallery. Repeated capture still requires preview/readability/Upload. NIC/DL retain selection and payment offers camera or gallery. On web/desktop, verify the documented recent-photo file fallback. HEIC that cannot be decoded must be rejected clearly. Simulate Android process destruction: user must retake/reselect; no stale recovered photo is auto-attached to a new account/revision.
14. Run new registration-attention, evidence and payment metadata tests plus updated registration/driver administration tests. Repeat Stage 10 lifecycle and Stage 11A–C navigation/support/privacy regressions at 360px and wide widths. Live rules/indexes/concurrency, real camera behavior and test/build results remain unverified.

## Live-device stabilization — all checks pending

No commands, analysis, tests, builds or deployments were performed in this pass.

1. Run the updated evidence, driver administration, registration attention, trip chat and Stage 10 service tests, then the existing Stage 10/11A–C regression suite. Check narrow/wide layouts.
2. Review/deploy the narrow Firestore chat_reads rules and new messages composite index (assignmentDriverId ASC, senderId ASC, createdAt DESC); wait for index readiness before testing unread indicators. No Storage rules, Functions, dependency, membership entitlement or payment-reference changes were made.
3. On an actual primary-admin session, open NIC/DL/selfie in registration_evidence and driver_evidence, and a payment_evidence slip. Repeat after granting a claim while the session was already signed in. Check forced-token refresh and successful private in-memory preview. Owner access must still work. Ordinary unrelated and supportAdmin-only users must remain denied, including direct SDK reads. Verify preview closes on owner removal/session gate removal.
4. Exercise denied Storage access, missing object, invalid reference and offline/download failures. Confirm distinct safe errors and retry; no public URL/token or private path in error messages. The original live failure needs confirmation: cached-token handling was fixed, but deployed bucket/project/rules and actual error code have not been inspected live.
5. Android/iOS: NIC and DL each offer Take photo and Choose from gallery; payment slip offers both; selfie offers only camera/retake. Cancel or deny camera access without falling back to gallery for selfie. Preparation, preview, readability checkbox and explicit Upload remain required. Confirm 2000px/2 MiB document/slip and 1600px/1.5 MiB selfie limits, JPEG 85/80 preparation and EXIF removal. Check web/desktop fallback.
6. Leave each payment claim field empty separately, especially Depositor name: Confirm must show the exact red error inline and next to the action. Check invalid/nonpositive amounts and invalid calendar dates. Missing slip upload must explain why claim submission is unavailable. Check required rejection/correction reasons and that registration Review scrolls to the first invalid input.
7. Sign in as pending, approved-but-unpaid, payment-verified/membership-pending and fully operational drivers. Authentication must succeed; only the last reaches Driver Dashboard. Others see registration/payment/activation explanations. Verify pending applicants remain blocked by service/rules and tourists retain their existing approval flow.
8. Admin approved application shows APPROVED registration and VERIFIED identity separately from payment/membership/account. No duplicate Verify identity action for application-managed accounts. Set account active/inactive/suspended must remain explicitly account controls with confirmation and existing authorization.
9. Start an accepted trip as its fully operational assigned driver, including a schedule one hour ahead. There is no early-start schedule gate in current source. Wrong driver, unaccepted trip and ineligible account must fail. Verify server anchor requestedBy/createdAt, exact startRequestedAt/startAutoStartAt and unchanged immutable parent fields; then creator confirmation/automatic timeout and end/completion regressions. If the live failure remains, record the new safe Firebase error category and trip/anchor state, and compare deployed rules with source. Do not remove security checks or describe this unresolved live issue as fixed.
10. Send a private chat message: the other participant sees a red dot on their trip/chat entry; the sender does not. Open the recipient chat and verify its persisted read cursor clears the dot across two signed-in devices/restarts. A later incoming message must restore it. Test simultaneous arrivals/read acknowledgements and stale writes; cursor cannot move backwards.
11. Reassign a trip and verify former driver cannot read messages or read cursors; new driver cannot receive the old assignment's unread state. Deny cursor writes to another UID, forged timestamps/message IDs, own outgoing messages, stale assignments, deletes and lists. Direct reads stay private. Message bodies/coordinates are never projected into public trip/profile/read-state data.
12. Background/close chat while new messages arrive: do not mark them read until reopening/foregrounding. Network failures saving a read cursor must show a retry explanation; no false delivery or fake local notification.
13. Future FCM stage: configure real platform messaging, private device tokens and trusted assignment-aware/idempotent delivery, token cleanup, permission/sound settings, privacy-safe payload and reauthorized navigation. Background/terminated delivery is NOT implemented by this pass.
