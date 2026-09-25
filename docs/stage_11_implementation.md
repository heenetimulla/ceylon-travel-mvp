# Stage 11: admin foundation, account management and support inbox

Implementation only; tests, analyzer, builds, package commands, Firebase and Git were not run. Earlier stage sections describe their original scope. The final registration-application section below supersedes number-only intake and normal-home routing for NEW accounts; legacy accounts retain their existing workflow.

## Authorization

Firebase Authentication custom claim `admin: true` (boolean) is the sole primary-admin authority. No accountType, profile document role, client preference or password check grants administration. The existing stored account types remain `tourist` and `driver`.

`AdminService.readAccess` reads the current Firebase user's ID-token claims. It handles signed out, denied, token failure and allowed states, bounds token reads to 15 seconds, and rejects results if the user changes while reading. `watchAccess` listens to `idTokenChanges`, clears the gate while checking, and ignores obsolete async results. The UI does not write claims. Firestore independently verifies the signed token on every query.

`AdminAccessGate` is reused by the Account entry and dashboard. Non-admins never instantiate the overview data loader. Directly constructing the dashboard still passes through the guard. UID changes replace the overview subtree, and sign-out/denial/errors remove the data. The service checks authorization before and after loading. No application-level admin cache is added; the preview explicitly requests `Source.server`, and count aggregations are server operations. Firestore SDK persistence may retain previously authorized document reads even with a server-source request. Sign-out removes the view but does not erase SDK caches, screenshots or other copies previously obtained by an authorized administrator.

The Account & Support screen contains the only new Admin Dashboard entry. It is hidden unless the trusted claim is present. Dashboard authorization is checked again on navigation. Signed-out, denied and claim-failure screens offer a check-again action that refreshes the ID token. After first granting a claim, sign out/sign in to refresh the Account menu. No user/driver dashboard was modified.

## Data and query definitions

| Card | Source/filter |
| --- | --- |
| Total Users | count of `users` documents |
| Total Drivers | `users.accountType == driver` |
| Total Tourist/User Accounts | `users.accountType == tourist` |
| Total Trips | count of `trip_posts` documents |
| Open Trips | `trip_posts.status == open` |
| Active Trips | status in accepted, start_requested, in_progress, end_requested |
| Completed Trips | status == completed |
| Open Support Requests | `support_requests.status == open` (excludes in_review) |

Counts include all matching documents, including inactive profiles. Total Users is the profile-document count, not a Firebase Authentication account census; Auth users without a profile are not counted. Legacy unknown account types can make role subtotals differ from the total. No values are fabricated or written back.

Eight count queries run in parallel with `support_requests.orderBy(createdAt, descending: true).limit(5)`. The preview reuses the existing SupportRequest model and displays reference, category, status, createdAt, lastMessageAt, userId and immutable submitted contactNumber. Dates display in the viewer's local timezone. Documents missing createdAt are excluded by Firestore ordering; missing dates in rendered records say Not available. No support message subcollection is queried and no full inbox/detail navigation is added.

The overview loads on entry and explicit Refresh; it is not a polling dashboard. Queries are separately consistent reads, not one atomic snapshot, so counts may differ transiently during concurrent changes. All queries have 20-second bounds. Any query failure displays an unavailable/retry state rather than partial or misleading totals. Existing single-field indexes support these queries; no new composite index is needed for Stage 11A. The Stage 10 messages index is unchanged.

## Firestore security changes and limitations

Added `isAdmin()` using `request.auth.token.get('admin', false) == true`.

- `users`: trusted admins may list (required for aggregation); existing owner get, exact create whitelist, metric-event updates and no-delete policy remain.
- `trip_posts`: trusted admins may list for counts. Existing get helpers, participant checks and all lifecycle/bid/cancellation write rules are unchanged.
- `support_requests`: trusted admins may read parent requests for counts/preview. Existing owner/staff access is preserved.
- No grants were added to private trip messages/location, bids, ratings, public projections, support messages or any other subcollection. Parent read permission does not cascade to subcollections.
- No admin writes, deletes, role assignment, verification, suspension or account-management operations were added.

**Important privilege boundary:** Firestore rules cannot distinguish an aggregate count from a document-list query. The trusted admin claim therefore permits listing complete private user/trip/support parent documents, not only counts or the five UI preview rows. The Stage 11A overview retrieves only aggregates plus five requests, but this is not a security cap on trusted admins. Stage 11B uses the same existing user-list permission for account browsing. Normal users do not gain these permissions. If a future staff role must receive totals only, implement a trusted aggregate/projection endpoint before granting that role access; do not grant this primary-admin claim. No broad wildcard admin rule was introduced, and `canGetTripPost` was not expanded (chat relies on it).

`supportAdmin: true` remains a separate existing support-staff claim, with exactly its previous read/reply/status powers. `admin: true` additionally satisfies parent-request read authorization only. It does not implicitly grant support replies, status transitions or conversation reads. Staff who need those powers must retain the explicit supportAdmin claim. A supportAdmin-only user does not receive this primary-admin dashboard.

## Manual configuration

There is no public admin registration and no user/driver "request admin access" workflow or admin request queue. Initial claims are provisioned only through trusted Admin SDK tooling. Any later staff/admin creation must be an already-authorized trusted super-admin/admin backend operation. Staff provisioning is not implemented in Stage 11A, and no client-side claim-setting functionality is permitted.

An operator with trusted Firebase Admin SDK access must create the initial login separately through trusted Firebase administration and provision its claims outside Flutter. No credentials or claim-setting endpoint/script was added to the client. Independently verify the target UID and environment first; never let an untrusted client choose a UID for promotion.

`functions/src/set_admin_claims.ts` is a local operator-only CLI. It is not an HTTP endpoint, callable function, application endpoint, Firestore request, public API or Flutter feature, and is not exported/imported by the Functions entry point. It uses only Firebase Admin SDK with Application Default Credentials (ADC) and an explicit GOOGLE_CLOUD_PROJECT. It accepts exactly an action and Auth UID, never a password, and never creates an Auth user. No keys, credentials, target UID or email are embedded.

After manually compiling the existing Functions project, run from the functions directory in a trusted operator shell:

```cmd
set GOOGLE_CLOUD_PROJECT=YOUR_PROJECT_ID
node lib/src/set_admin_claims.js grant <UID>
node lib/src/set_admin_claims.js revoke <UID>
```

Replace the placeholders before running; choose one action. Configure ADC separately using the approved operator authentication/impersonation workflow. The credential must have permission to read the target Firebase Auth user and update custom claims in the selected project. Do not place service-account JSON keys in the repository. Missing project/UID, unsupported action, unavailable ADC and nonexistent users cause a nonzero exit with a safe error; raw SDK errors, credentials, tokens and profile details are not logged.

Grant reads existing customClaims and sets both `admin: true` and `supportAdmin: true`, preserving all other keys. Thus this operator command intentionally provisions primary-admin and existing support-staff privileges together; it does not merge the two authorization systems. Revoke reads existing claims and removes both keys, preserving unrelated claims, including other roles. Both operations copy the claims object and are safe to repeat. Successful output identifies only the operation and UID.

Custom-claim updates replace the complete claims object in Firebase Auth, so this read/modify/write cannot be atomic against another operator updating claims simultaneously. Serialize claim-maintenance operations for a given UID. After either grant or revoke, sign out/sign in or force-refresh the ID token; existing signed tokens retain the usual validity window. The tool does not revoke refresh tokens or manage sessions automatically.

Offline helper tests in `functions/test/set_admin_claims.test.ts` cover preservation, removal, repeat operations and CLI validation. Importing the helpers does not initialize Firebase, fetch ADC or perform network requests because the CLI is guarded by `require.main === module`. No tests, builds or provisioning commands were run by Codex.

Use an existing registered account/profile to access the application's normal authenticated Account screen. Do not rename its accountType to admin. Sign out/sign in after granting claims. Deploy the updated Firestore rules manually before using the overview. No new dependencies, Functions, indexes, Storage setup or Firebase project settings are required.

Custom claims are cached in ID tokens. Revoking a claim does not invalidate every already-issued token immediately; tokens can remain valid until expiry (typically up to about an hour). Use the trusted Auth session-revocation process as appropriate, and account for Firestore's token-validity window. The client gate is not an immediate server-side revocation mechanism. Protect operator credentials and restrict claim-setting IAM access.

Counts incur aggregation/index-read charges and grow with collection size. The preview reads at most five records per load; manual refresh avoids constant polling costs. There is no analytics cache, daily report delivery or backend aggregation job in 11A.

## Files and tests

Created:
- lib/core/models/admin_dashboard_stats.dart
- lib/core/services/admin_service.dart
- lib/core/services/admin_data_source.dart
- lib/core/widgets/admin_access_gate.dart
- lib/core/widgets/admin_stat_card.dart
- lib/screens/admin/admin_dashboard_screen.dart
- test/stage_11_admin_test.dart
- docs/stage_11_implementation.md
- docs/stage_11_manual_verification.md

Modified only lib/screens/auth/account_screen.dart and firestore.rules.

Tests cover strict claims, unauthenticated/non-admin denial before reads, service query counts (including all four active states), preview limit/order/source, hidden/visible Account entry, direct-route denial, loading, error, stats, empty support, contact snapshot display, sign-out removal and mobile/desktop widths. AdminService uses an injected AdminDataSource with a production Firestore adapter; tests implement the small Dart interface rather than subclassing sealed Firebase queries/snapshots. The adapter retains the same query filters, server source and preview limit; service authorization checks and timeouts remain unchanged. Tests do not execute the Firebase adapter against a server or exercise Firestore rules. Manual security checks are in the verification document.

The watcher regression test consumes explicit loading/signedOut events, resolves a controlled obsolete allowed claim result, then uses another signed-out auth event as a delivery barrier. It no longer assumes that two microtask turns drain stream delivery. The production watchAccess generation guard and authorization behavior are unchanged.

Stage 11A originally deferred individual account/driver management; Stage 11B adds its read-only portion. Stage 11C adds the support inbox/actions described below. Verification actions, staff role management, destructive account operations, analytics, reports, payments and other later Stage 11 features remain deferred. Stage 10 production services, Functions/Cloud Tasks, chat assignment privacy, location, ratings, customer support writes and theme are unchanged.

## Stage 11B: Admin User & Driver Management

The dashboard now includes **Users & Drivers**, leading to a paginated account browser and a separate read-only detail route. Existing overview counts and recent support requests retain their Stage 11A queries and behavior. Both new routes instantiate their loaders only inside `AdminAccessGate`. The shared `AdminService` is passed through navigation, with optional dependency injection for focused tests.

### Read-only architecture and security

- `AdminUserSummary` retains only UID, name, account type, email, phone, city, status, profile photo path, completed/cancelled trip counts, cancellation rate, average rating, rating count, verification status and created/updated dates. UID comes from the document ID, not the profile field. Missing/null/malformed optional values become unavailable instead of crashing or inventing zeroes. Unknown account types are labeled Unknown; stored tourist/driver values are not migrated.
- `AdminUserDataSource` is a read-only interface with a production Firestore adapter. `AdminUserQuery` describes the actual bounded requests so tests can capture them without mocking sealed Firestore types. Query logic stays outside widgets.
- `AdminService.loadUsers` and `loadUser` require the boolean `admin: true` claim before reading, then recheck authorization and the same signed-in UID before returning results. Reads have a 20-second timeout and use `Source.server`. Existing gate behavior removes the subtree on sign-out, claim-check loading/failure/denial or account change. Obsolete pagination/filter responses are ignored after a new request or disposal.
- `supportAdmin` alone does not grant account management. No profile admin fields, public registration, admin request flow, UID allowlist or claim-writing code was added. No writes/deletes are exposed by the new data source or screens.
- `firestore.rules` is unchanged for 11B. Details use the already-authorized list operation constrained to one document ID; direct `users/{uid}.get()` remains owner-only. No new permissions are necessary.
- Firestore returns complete documents for mobile/web collection queries, but only the operational field allowlist is retained by the model or shown. No verification evidence/rejection reason, vehicle documents, message threads, GPS, claims or credentials are displayed. Profile photo paths are text only; no image, Storage or arbitrary URL fetch is attempted. Existing SDK persistence and token-revocation caveats above still apply.

### Exact queries and browsing behavior

| Operation | Firestore request |
| --- | --- |
| All accounts | `users.orderBy(FieldPath.documentId).limit(50).get(Source.server)` |
| Tourist/User | Same query with `where('accountType', isEqualTo: 'tourist')` |
| Driver | Same query with `where('accountType', isEqualTo: 'driver')` |
| Subsequent page | Same selected filter/order/limit with `startAfter([lastDocumentId])` |
| Account detail/refresh | `users.where(FieldPath.documentId, isEqualTo: uid).orderBy(FieldPath.documentId).limit(1).get(Source.server)` |

Ordering is ascending document ID, deliberately not createdAt: ordering on that optional field would silently exclude older profiles without it. No backfill or composite index file change is included. Standard accountType single-field indexes are expected to serve equality plus ascending document ID ordering; live query/index verification remains pending.

Pages contain at most 50 documents. A full page offers Load more; if the collection is an exact multiple of 50, one final empty query establishes completion. All `users` profiles can be browsed, including legacy unknown account types under All. Auth-only registrations without a `users` document cannot be enumerated by this client and are outside this profile browser.

Search is local, case-insensitive substring matching across the loaded names, emails and phones, with punctuation-insensitive phone matching for phone-shaped searches. The UI explicitly says **Search loaded accounts**, shows loaded/matching counts, and keeps Load more available when the current search has no matches. There is no global full-text search or automatic collection scan. The exact role filter runs on the server and resets pagination while retaining search text. Changing filter mid-request discards the old response. Each explicit Load more requests only one page; earlier pages stay in memory until refresh, filter change or gate disposal. Thus per-request reads are bounded, while session memory grows with intentional browsing.

Refresh clears previous list data and starts again; detail refresh hides the prior snapshot while loading. Paging errors retain already loaded rows and offer retry at the same cursor. Errors do not expose raw backend diagnostics. Empty results, unavailable detail, missing profile and loading are distinct states. Paging is not an atomic snapshot; newly created IDs before the current cursor or concurrent profile edits require Refresh. Detail reads are fresh and can differ from a previously loaded card.

Rates follow the existing stored percentage convention (0–100), displayed with one decimal place. Ratings display one decimal place. Driver verification falls back from `verificationStatus` to the existing private `verification.status` field. Dates use the viewer's local timezone. Unknown fields remain unavailable; photo-path presence does not assert that an image exists or was verified.

### Stage 11B files and verification status

Created: `lib/core/models/admin_user_summary.dart`, `lib/core/services/admin_user_data_source.dart`, `lib/screens/admin/admin_users_screen.dart`, `lib/screens/admin/admin_user_detail_screen.dart`, and `test/stage_11b_admin_users_test.dart`.

Modified: `lib/core/services/admin_service.dart`, `lib/screens/admin/admin_dashboard_screen.dart`, and both Stage 11 documentation files. Existing `test/stage_11_admin_test.dart` is retained unchanged to cover Stage 11A regressions.

New focused tests cover service and direct-route denial, bounded query definitions/cursors/server source, authorization changes during list/detail reads, dashboard/list/detail navigation, loading, both roles, all three filters, name/email/phone search, stale filter responses, pagination retry, empty/error/missing-account states, legacy optional fields, read-only controls and detail fields at mobile/desktop widths. These tests use an ordinary Dart data source, not live Firebase; they do not establish Firestore rule/index correctness.

No commands, tests, analyzer, builds, emulator sessions or manual/live UI checks were executed for 11B. The current branch and supplied Stage 11A commit are assumed from the user's context and were not checked with Git. All verification in the Stage 11B checklist in `stage_11_manual_verification.md` remains pending.

**Deferred explicitly:** delete, password reset, accountType changes, admin promotion, suspension, profile edits, driver approval/rejection and all other destructive/account-change operations. These may belong to Stage 11D; no part of them is implemented here.

## Stage 11C: Admin Support / Complaint Inbox

Stage 11C adds Support & Complaints to the admin dashboard, retaining all existing statistics, recent support preview and Users & Drivers navigation. A separate claim-gated entry on Account & Support makes the same inbox available to support-only staff without admitting them to the primary-admin dashboard. Stage 11A/11B production services and account permissions are unchanged. The user reports Stage 11B live UI verification complete at commit `bd89f59`; branch/base are supplied context, not independently checked with Git.

### Authorization decision: approach B

Only the boolean Firebase Auth custom claim `supportAdmin: true` grants inbox, thread, reply and status-management access. Primary `admin: true` alone keeps its existing parent-request reads but cannot enter the staff inbox, read others' message threads/audit history or perform staff writes. Normal owners retain their existing own-request conversation permissions. An owner who happens to have only the primary-admin claim still acts as an ordinary owner, not staff.

The existing trusted operator CLI grants both admin and supportAdmin. Primary admins needing this feature must have both claims and refresh/sign in again; there is no automatic client promotion. Support-only staff use the Account entry and do not gain user-list/trip-list/admin-dashboard permissions. No profile field or accountType grants staff access.

`AdminSupportService` reuses the existing AdminService token watcher/gate lifecycle with its own support-claim check. Both routes pass through `AdminSupportGate`; the generic gate's new optional messages preserve its existing defaults. Reads check access before and after completion and reject changed UIDs. Transactions capture the authenticated UID, check it again inside each transaction attempt, and let Firestore independently enforce the current token's permissions. UI generations/disposal prevent obsolete reads from being displayed. Issued-token revocation and SDK-cache caveats still apply.

### Architecture and data

- `admin_support_data.dart`: existing SupportRequest/SupportMessage models reused through a tolerant admin projection; stored status constants, filter/search helpers, timestamp/ID cursor, generic pages and immutable status-event model. It does not modify the existing customer parsers or write schema.
- `admin_support_data_source.dart`: server-source bounded queries and Firestore transactions behind a small injectable interface. `SupportStaffWrites` defines the exact production payload allowlists used by the adapter and tested directly.
- `admin_support_service.dart`: authorization, validation, read timeouts, actor checks and orchestration. Widgets contain no Firestore queries or writes.
- Inbox: loading/error/retry/empty states, status filters, local search, cursor paging and refresh. It refreshes on return from a detail route. Detail: original request, automatic acknowledgement, immutable submitted contact, requester name/role/UID, optional human-readable trip reference, timestamps with year, paged conversation and audit history, reply composer and status controls.

Identity comes only from the support request's existing submitted userName/userRole/userId snapshot. No extra private-profile fetch or email lookup is added. Original contactNumber is never replaced with a current profile phone. Trip linkage is optional; general Contact Us requests need no trip. Existing complaint subcategory labels are reused. No complaint triggers penalties, ratings changes or account actions.

### Exact read queries

All requests use `Source.server`; read operations have a 20-second bound. Page size is 50.

| Read | Query |
| --- | --- |
| Inbox All | `support_requests.orderBy(createdAt, descending: true).orderBy(documentId, descending: true).limit(50)` |
| Status filter | Same, with `where(status, whereIn: selectedStatuses)` |
| Detail parent | `support_requests/{id}.get()` |
| Messages | `support_requests/{id}/messages.orderBy(createdAt).orderBy(documentId).limit(50)` |
| Status history | `support_requests/{id}/status_history.orderBy(createdAt).orderBy(documentId).limit(50)` |
| Next page | Same query plus `startAfter([rawCreatedAtTimestamp, documentId])` |

Cursors retain raw Timestamp precision and use document IDs to break ties. Inbox ordering is newest-created first, avoiding moving last-message cursors during conversations. Messages/history are oldest-first with explicit Load more controls; every page is reachable. The full original request and generated acknowledgement are shown separately, consistent with the existing customer thread. The acknowledgement is not a fabricated stored message.

The new composite index is `support_requests(status ASC, createdAt DESC)` with the default descending document-name tie-breaker. Existing indexes are retained. No dependency upgrades are required.

Search covers only loaded rows in the selected filter: support/trip reference, contact number (including digit-normalized searches), submitted name, UID, category/subcategory and subject. There is no global full-text query, email lookup or automatic full-collection scan. Filtering is server-side using exact stored values. A full page offers another page; an exact multiple of 50 needs a final empty read. Previously loaded rows stay in memory until refresh/filter change/disposal, so per-query reads are bounded while intentional browsing can grow session memory.

There is no polling or live listener in the admin inbox/thread. Staff use Refresh to receive later replies/status changes; successful writes reload the first conversation/history page. Load more reaches subsequent messages, including a newly sent reply in a long thread. The customer thread's existing live listener remains unchanged. Separate reads/pages are not a single consistent snapshot. A request that changes status between filtered pages may require refresh; IDs are deduplicated locally.

`createdAt` is required by the existing support-create/reply rules. Ordering excludes any out-of-schema historical records missing that field; no migration/backfill is performed. Optional trip fields and missing/malformed display data are safe. Date parsing retains Firestore Timestamp and DateTime instants in UTC, with local display. Unknown statuses display as stored but cannot be changed through this workflow.

### Replies and retry behavior

A reply transaction reads the parent and the selected new message document. It rejects missing/closed requests, then appends exactly `id`, authenticated `senderId`, `senderRole: admin`, trimmed `message` (1–4000 characters) and server `createdAt`. The same transaction updates only parent `updatedAt`, `lastMessageAt` and `lastMessageId`. Previous messages are never overwritten, edited or deleted. The customer UI already labels the admin role as Support team.

The client allocates an operation ID once for a draft submission and retains it on an unconfirmed result. Retrying unchanged text uses that same ID. If the transaction finds that ID with the same actor/role/text, it returns without another write; conflicting reuse fails. Editing the draft begins a new operation. Status operations use the same approach with actor/from/to. This idempotency is scoped to the retained screen operation: closing the screen loses the pending ID, so after an ambiguous outcome staff should refresh/check history before composing another action. No reply is fabricated locally. The screen clears the draft only after confirmed success. There is no additional client timeout or automatic retry loop around mutations; Firestore manages transaction retries.

### Status workflow and append-only audit

Stored states remain **open**, **in_review**, **resolved**, **closed**. In Progress is only the display label for in_review. The inbox combines resolved/closed in one filter; the detail selector keeps them distinct. Staff may deliberately transition between distinct supported states, including reopening closed requests. No automatic closure or migration occurs. Closed requests reject replies under the existing rules until explicitly reopened. Resolved requests still permit replies, matching the previous schema.

A status transaction compares the current stored status with the displayed expected status. Concurrent status changes fail safely and require refresh. It writes only `status`, server `updatedAt` and `lastStatusEventId` on the parent, and creates `status_history/{operationId}` containing only `id`, authenticated `actorId`, `fromStatus`, `toStatus`, server `createdAt`. No owner/reference/category/contact/trip/original-message/creation-time or last-message metadata changes are permitted. Each successful transition is attributed and timestamped. Old transitions before this feature cannot be reconstructed and are labeled accordingly; there is no invented audit history.

### Narrow rule change

Parent support reads, all message rules and all unrelated collection permissions retain their existing scope. The former supportAdmin status-update branch now additionally requires a matching **new** status_history event in the same atomic write. The event rule checks the before/after parent status, actor, allowed states, changed status, server timestamps, pointer and exact parent/event field allowlists. Status-only writes without history, history-only writes, forged actors and changing immutable parent fields must fail.

The new status_history subcollection is readable only by supportAdmin, create-only through that linked validation, and never updateable/deletable. Parent and message deletes remain denied; message updates remain denied. The change tightens existing status-writing semantics rather than granting primary admins new powers. Any external legacy staff client that wrote status directly without audit must be updated before using the new rules; there was no such Flutter staff writer in this repository. Deploy the narrow rules and index manually before enabling Stage 11C writes.

### Files, tests and verification status

Created: `lib/core/models/admin_support_data.dart`, `lib/core/services/admin_support_data_source.dart`, `lib/core/services/admin_support_service.dart`, `lib/core/widgets/admin_support_components.dart`, `lib/screens/admin/admin_support_inbox_screen.dart`, `lib/screens/admin/admin_support_detail_screen.dart`, `test/stage_11c_admin_support_test.dart`.

Modified: `lib/core/widgets/admin_access_gate.dart` (optional support-specific text only), `lib/screens/admin/admin_dashboard_screen.dart` (navigation and injected test service), `lib/screens/auth/account_screen.dart` (staff entry), `firestore.rules`, `firestore.indexes.json`, and these two Stage 11 documents. Existing customer support service/models/screens and Stage 11A/11B test files are unchanged.

Focused tests cover strict support claims, denied reads/writes, exact mutation payloads/immutable parent fields, existing status whitelist, query filters/cursors, stale reads, search, loading/error/empty/retry states, staff/dashboard navigation, optional trips, submitted contact, history display, reply operation IDs, status selection, closed-request behavior, sign-out disposal and 360/1400px layouts. Pure Dart fakes exercise the service/UI boundaries; they do not establish live transaction, index or rules correctness. Detailed negative server checks are in the manual verification document.

No commands, analyzer, tests, build, emulator/manual UI testing, Firebase, Git, npm or package upgrades were executed. No branch merge or deployment was performed. All Stage 11C verification remains pending with the user. No suspension, approval, role management, account deletion, automated penalties, notifications, reports or analytics were added.

## Stage 11D — driver verification, registration payments and membership

Stage 11A–C completion is supplied by the operator. Stage 11D adds driver-only administration to Users & Drivers account details and an owner submission entry under Account → Driver verification & membership. Tourist details remain read-only and have no driver controls. Existing dashboard statistics, Users & Drivers navigation, Support & Complaints and support authorization are unchanged. No commands, tests, builds, deployments, package changes, branch operations or manual UI checks were performed for Stage 11D.

### Trusted service boundary and authorization

Flutter uses `DriverAdministrationService` and its injectable data source. It can create an immutable request in `users/{uid}/driver_operations/{operationId}`, then waits for a server-confirmed result. The new `processDriverAdministration` Firestore trigger processes requests through `processDriverOperation`. This uses existing Admin SDK/Functions dependencies, with no callable SDK dependency or direct privileged Flutter transaction.

Only an authenticated **admin: true** principal can request identity/payment reviews, membership activation or account-status changes. **supportAdmin alone does not grant Stage 11D powers.** Owners can request only their own identity submission, payment reference and payment claim. The worker rechecks the actor using Firebase Auth, including disabled status and current boolean admin claim, before processing. Every target must be a driver. A revoked/disabled actor fails safely when processed. Auth and Firestore are separate systems; authorization is checked at worker start, not atomically with an Auth record.

Rules permit only a narrowly shaped pending operation request with authenticated actor, server creation time, integer expected revision, allowed action, bounded reason and an allowlisted payload. Backend validation applies stricter per-action keys and value checks. Owners/admins cannot update/delete operations. Operation payloads can contain private identity information; they are readable only by that owner or primary admins and must be treated as sensitive records, not analytics or logs. Errors expose safe domain messages only.

### Identity and uniqueness

`driver_verifications/{uid}` holds raw entered NIC/DL values, private evidence references, review metadata and `identityVerificationStatus` (pending/verified/rejected). Each submitted version is also appended to `driver_verifications/{uid}/submissions/{operationId}`. Owners cannot replace a verified identity. Primary admins manually review the submitted NIC/licence numbers using the approved manual process; legacy number-only intake remains supported; NEW applications require the role-specific evidence described in the final application section; rejection and all other admin decisions require a confirmation dialog with optional reason.

NIC/DL claims are transactionally reserved in `identity_registry/{HMAC}` with identifier type, UID and claimedAt. No raw identifier is used as a document ID. Normalization uppercases and removes whitespace/hyphens. Old-format NIC YYDDDSSSSV/X maps to 19YYDDD0SSSS so old/new aliases share a claim; new NICs require 12 digits, and licences require 6–20 alphanumeric characters. This is format/canonicalization logic, not external identity validation. Document authenticity still requires manual review. Duplicate NIC or DL claims by another account fail without partial writes, including concurrent submissions.

`DRIVER_IDENTITY_HMAC_KEY` is a server-bound Secret Manager value of at least 32 UTF-8 bytes; use cryptographically random high-entropy material. There is no embedded production secret or client hash fallback. A fingerprint in `system_config/driver_identity_registry` is established on first use and checked on identity submission and bank verification. Changing the secret fails closed. Key rotation requires an operator-planned registry migration; no rotation tool is included. Claims are retained after rejection/correction to prevent identifier reuse; disputed/incorrect claims require a separate trusted operator procedure, not client deletion.

Only the high-level identity status goes in users/{uid}. The public-profile projection exposes only its existing verification label, preferring the new trusted status when present; raw NIC/DL, evidence, payment and membership details are not added to public profiles.

### Manual bank payment model

The owner requests a server-created registration quote in `users/{uid}/payments/{paymentId}`. The backend reads the trusted founding-offer cutoff state in the registration counter transaction to issue the initial quote. It creates a unique `CT-PAY-YYMMDD-<12 uppercase hex characters>` reference and reserves it in `payment_reference_registry`; collisions fail safely. A quote does **not** reserve an official driver registration number. The driver can include the reference in the bank transfer/deposit.

The driver submits a whole-LKR claimed amount, payment date (YYYY-MM-DD), transaction reference, depositor and private slip reference once. Submitted claim fields cannot be edited. Payments use pending/verified/rejected; terminal reviewed records cannot be changed through this workflow. Primary admins verify against actual bank records and supply a canonical unique bank-record reference, or reject with an optional reason. A server HMAC registry (`payment_bank_registry`) prevents a bank reference being credited twice. Use a consistent bank/statement/transaction identifier that is unique across receiving accounts; this is manual confirmation, not a bank integration.

Verification requires claimed amount and the credited total to equal the stored quotedRegistrationFeeLkr, with a consistent server-issued entitlement. It does not use the current counter to price an existing quote. It atomically updates payment metadata, the trusted registration total, user payment status and audit. Verified payments are never overwritten. A rejected claim can be followed by a replacement payment request carrying the original quoted terms and quotedAt; rejection does not remove the user’s entitlement. There is no automatic refund or bank reconciliation.

Quote entitlement is locked at issuance. Each payment quote persists quotedRegistrationFeeLkr, quotedMembershipPlan, quotedAnnualRenewalRequired, quotedAnnualRenewalFeeLkr, quotedAt and foundingOfferOpenAtQuote alongside paymentReference/status. Before closure the terms are 3500/founding_lifetime/false/null/true; afterward new entitlements are 5000/standard_annual/true/10000/false. A valid pre-cutoff LKR 3,500 quote remains lifetime even if payment verification and activation happen after closure at registration 101, 102 or later. No additional registration payment is requested for an already credited quote.

The identity form accepts NIC and driving licence numbers, with optional private NIC/licence/selfie photos added by the evidence correction below. Number-only intake remains supported. New payment claims now require a privately uploaded slip image; bank instructions remain operator configuration. Existing issued references are unchanged. Historical text references remain readable only in private details and are never opened as arbitrary URLs.

### Membership and counter transaction

The trusted backend alone reads/increments `system_config/driver_registration_counter.nextRegistrationNumber`. It must be explicitly initialized by an operator with foundingOfferClosed (false through next number 100, true afterward); missing/inconsistent state fails closed rather than reopening the offer or resetting the counter. `driver_registration_registry/{number}` additionally prevents reuse of an assigned number.

Activation rechecks driver account type, both high-level and private verified identity, verified payment, no existing membership assignment, and the exact verified registration total. It loads and validates the stored quote, then in one transaction assigns the number, increments the counter, creates the number registry, activates membership using the quote entitlement and appends audit. The registration number is sequence/order identity; the quote is the commercial entitlement. The number never overrides an earlier quote.

| Initial quote issuance | Plan | Registration fee | Annual renewal | Initial validity |
| --- | --- | --- | --- | --- |
| Before the 100th successful activation | founding_lifetime | LKR 3,500 | Not required; fee null | Lifetime; membershipValidUntil null |
| After founding offer closure | standard_annual | LKR 5,000 | Required; LKR 10,000 | First UTC calendar anniversary of activation |

Activation #100 also atomically sets foundingOfferClosed true, foundingOfferClosedAt and foundingOfferClosedByRegistrationNumber (100), and creates exactly one immutable `admin_notifications/founding_offer_closed` document. Its type is founding_offer_closed, title is “Founding offer closed”, registrationNumber is 100, read is false and createdAt is server time; the message announces #100 and new LKR 5,000 quotes. The fixed event ID and transaction prevent duplicate events on retries or competing #100/#101 activations. New quote issuance reads the same counter document, so a race is serialized: a quote committed before closure keeps founding terms, while an initial quote committed after closure gets annual terms. More than 100 drivers may ultimately receive lifetime membership because pre-cutoff quotes remain valid.

The closure event allows primary-admin get access only; all client creation/update/delete/list operations are denied, including marking read. It is available as a trusted operational record. The optional Flutter dashboard banner remains pending; no dashboard redesign or generic notification system was added.

The standard initial one-year term is an explicit implementation assumption; February 29 clamps to February 28 the following year. It is not a date waiver. No `firstAnnualRenewalWaived`, promotions, referral vouchers or annual renewal payment automation are implemented. Renewal_due/expired are reserved membership states; no scheduled transition or automatic renewal is added.

Users retain separate identityVerificationStatus, paymentStatus, membershipPlan, membershipStatus and accountStatus. Server-managed helpers are driverAdminRevision, currentRegistrationPaymentId, registrationPaidTotalLkr and membershipActivatedAt. Existing legacy `status` is not overwritten. Missing accountStatus defaults from legacy active status, otherwise inactive. `paymentStatus: not_required` is not a way to bypass paid driver activation.

Membership activates an account for many trips, with no commission, per-trip charge or trip quota. Manual account states are active/inactive/suspended. No complaints, ratings, cancellations or other statistics trigger an automatic decision.

### Existing centralized bidding boundary

The repository already centralizes bid authorization in `validBidDriver` and bid acceptance in `validSelectedBidAcceptance`. These now require driver + verified identity + verified payment + active membership + active account. Annual memberships also require a future validity timestamp; lifetime memberships have no expiry. The existing BidService submission preflight uses the same eligibility model. Acceptance of an old bid is checked again against current driver eligibility.

This affects new bidding and accepting an existing bid, including legacy drivers missing approval fields. Existing assigned-trip completion/history, support and customer access are not blocked by the new guard. Coordinate existing-driver verification and rollout before enabling these rules. No bulk migration/backfill or unrelated bidding refactor is included. Annual expiry blocks new operational activity without automatically mutating stored membershipStatus; a future trusted renewal workflow is required.

### Reads, immutable history and concurrency

Admin profile loading reuses the permitted users query constrained to document ID with limit 1; owners get their own document. Identity uses a single private document get. Payments/admin_history/driver_operations initially load at most 20 each, ordered by createdAt descending then document ID descending. Payments and admin history expose cursor paging; recent operation results are bounded to 20. New records always have server createdAt; older records missing it are excluded by ordering. These reads use server source; separate reads are not a single consistent snapshot. No new composite index is required by these queries.

Every successful admin state change creates `users/{uid}/admin_history/{operationId}` with action, previousValue, newValue, actorUid, optional reason, createdAt and operationId in the same transaction as business state. Audits and identity submission history cannot be updated/deleted by any client. Payment reviews preserve the submitted claim. No audit includes raw NIC/DL. All financial, registry and membership writes are server-only.

Expected driverAdminRevision prevents stale actions. Firestore transaction retries serialize competing registration assignments, identity claims and payment reviews. The operation result commits atomically; replay of a completed operation does nothing. A repeated activation with another operation ID returns alreadyActivated without assigning a number or duplicating audit. Each real state change increments the revision. The UI retains an operation ID for unchanged retries until refresh, disables actions while a loaded operation is pending, and never presents an optimistic approval. A timeout means the request may still complete; refresh its recorded result before creating a new action. Infrastructure errors retry via the trigger; domain errors mark the operation failed without domain writes. Loading generations and mounted checks prevent disposed/obsolete reads from replacing current UI state.

### Firestore permission changes

No generic admin writes were added to users/{uid}; existing profile/metric rules remain intact. All Stage 11D high-level fields, counter, registries, identity/review documents, payment documents and audit events are Admin SDK managed. Private identity/current submissions and payments are readable by owner/primary admin. Admin history is readable by primary admin only. Operations are readable by owner/primary admin and create-only through the restricted rule; no client can forge a completed result. Config and registries have no client permissions. No delete permission, role assignment, accountType/contact/profile/ratings/metric edit permission was added. SupportAdmin behavior is unchanged.

### Files and focused coverage

Created: `functions/src/driver_administration.ts`, `functions/src/driver_administration_trigger.ts`, `functions/test/driver_administration.test.ts`, `lib/core/models/driver_administration.dart`, `lib/core/services/driver_administration_service.dart`, `lib/core/widgets/driver_administration_panel.dart`, `lib/screens/driver/driver_registration_status_screen.dart`, `test/stage_11d_driver_administration_test.dart`.

Modified: Functions `index.ts` and `public_profiles.ts`; Flutter `admin_user_summary.dart`, `bid_service.dart`, `admin_user_detail_screen.dart`, `account_screen.dart`; `firestore.rules`; these two documents. No index changes. The subsequent evidence correction adds the three pinned Flutter dependencies listed below.

New backend contract tests cover authorization, unique identities and races, HMAC failures, payment claims/reviews, duplicate bank references, wrong amounts, immutable verified payments, locked quote terms, cutoff closure/event uniqueness, pre-cutoff entitlement after closure, activation prerequisites/idempotency/concurrency, counter collisions, stale revisions, allowed account changes, protected profile fields and safe public projection. Flutter tests cover safe legacy display/eligibility, denied access, driver-only controls, exact queued requests, confirmation dialogs, review actions, activation prerequisites, owner submission, disposed responses, 360/1400px layouts and existing dashboard entries. Contract fakes do not prove deployed Firestore rules or event delivery; live negative/security checks remain pending.

### Required operator setup — not performed

Set DRIVER_ADMIN_REGION (default asia-southeast1), provision a dedicated DRIVER_ADMIN_SERVICE_ACCOUNT and grant its necessary Firestore transaction, Firebase Auth user-read and bound-secret access permissions. Supply the HMAC secret securely. Initialize the counter and cutoff fields once from authoritative existing assignments (1 and foundingOfferClosed false only for a genuinely fresh registry), never reset/reuse numbers, and preserve all registries/fingerprints. Deploy the new trigger, changed public-profile projection and narrow rules using the project's normal reviewed deployment process; do not merge branches as part of this stage. Configure private Storage evidence access as described below, retention procedures and bank instructions. The manual verification document lists all pending checks, including security, concurrency and coordinated legacy-driver rollout.

### Quote-lock correction: compatibility and verification

No automatic historical rewrite is performed. Before enabling this correction, a trusted operator must reconcile any existing Stage 11D quotes lacking the new entitlement fields against their original server-issued amount/reference/time, preserving valid founding entitlements. Missing/inconsistent quote metadata fails closed for review; the worker never infers entitlement from the eventual registration number. Preserve original verified financial records and use an audited operator migration for metadata if necessary. Already activated accounts are not repriced. Existing cutoff state beyond #100 must be initialized from authoritative history, including the one closure event, before resuming operations. No live data or configuration was changed here.

The correction modifies only the driver worker/tests, driver panel wording/quote display, focused Dart tests, the single-event read rule and these documents. The public test helper accepting a private fake service is now `_panel`, resolving library_private_types_in_public_api without suppression. Identity/HMAC, support, dashboard statistics, counter uniqueness and existing write permissions remain unchanged. All analyzer, test, build, security-rule and live concurrency verification remains pending.

### Driver identity UI correction

Driver Dashboard and Account now expose “Driver verification & membership”, opening DriverRegistrationStatusScreen. Legacy accounts retain their existing home flow. New Tourist and Driver accounts use the application status route until operational; tourists never receive driver payment/membership controls. The owner panel renders inline NIC/licence inputs when no submission exists and on rejection. Validation requires trimmed, nonempty values of at most 40 characters; normalization and definitive format/uniqueness checks stay on the existing worker. The form sends nicNumber/drivingLicenceNumber through submit_identity, preserving expectedRevision, authenticated actor and operation-ID retry protection. The subsequent evidence correction optionally includes a map of private uploaded paths. No direct profile or identity-registry write was added.

A confirmed submission displays “Identity submitted for admin review”. Pending submissions have no normal resubmit form, and uncertain transport outcomes pause another identity submission until refresh. Rejection displays the reason and permits corrected numbers using the latest revision; old submissions and registry claims remain intact. Owner summaries mask all but the final four characters. Raw numbers appear only while entered in the private owner form and in the dedicated private admin review; normal/public profiles and account lists remain unchanged. Controllers clear after success and are disposed with the screen.

The minimal backend compatibility change accepts absent document/selfie references as null and removes their presence as a prerequisite for manual admin review. It does not change HMAC normalization/uniqueness, admin authorization, transactional history, payments, membership terms or Firestore rules. No placeholder document values or automatic identity approval is introduced. Optional Storage evidence was added in the correction below. The corrected worker must be deployed by the operator before number-only submissions can succeed against an older deployed worker.

The Account screen prompts ineligible drivers to complete verification; the owner panel and BidService preflight use “Complete driver verification and membership activation before submitting bids.” Permission-denied submission errors also give verification/membership guidance without weakening rules. Focused tests cover inline inputs, empty validation, number-only payload, pending/masking, rejection/resubmission/revision, tourist exclusion, private admin review, normal-list privacy and number-only backend review. Tests/analyzer/builds/live checks were not run.

### Private registration photos and local image preparation

The legacy owner identity form optionally accepts NIC, driving licence and selfie photos before submit_identity. Rejected applicants may submit replacement photos against the latest driverAdminRevision. Pending/verified submissions have no normal replacement form. Number-only submissions remain valid; this does not change identity policy, HMAC uniqueness, review authorization, quote entitlement, fees or membership activation.

**Local processing:** pinned new dependencies are image 4.5.4 (pure Dart codec), file_selector 1.0.4 (system file picker), and firebase_storage 13.4.5. No dependency resolution, upgrade, installation or lockfile regeneration was executed. EvidenceImageService validates extension plus JPEG/PNG signatures, decodes locally, rejects malformed/animated images, applies camera orientation, downsizes without upscaling, flattens transparency onto white and re-encodes a fresh RGB canvas. EXIF/GPS and original filename metadata are not copied. Original bytes never go to Storage. HEIC/HEIF, PDFs, archives and other formats are rejected with a JPEG/PNG instruction; no ZIP workflow exists.

| Evidence | Maximum long edge | JPEG quality | Maximum uploaded size |
| --- | --- | --- | --- |
| NIC / driving licence | 2000 px | 85, or 80 if needed; 4:4:4 colour | 2 MiB (2,097,152 bytes) each |
| Selfie | 1600 px | 85, or 80 if needed; 4:4:4 colour | 1.5 MiB (1,572,864 bytes) |

EvidenceImagePolicy centralizes client limits. Original selection is capped at 20 MiB, 24 megapixels and 12,000 px on either edge before full decoding. Minimum short edge is 400 px both before and after resize; minimum original long edge is 800 px for documents / 600 px for selfies. If quality 80 still exceeds the cap, reject rather than repeatedly destroying resolution/quality. Change matching Storage/backend caps together when changing production policy.

The UI shows Preparing image..., a local optimized preview, zoom inspection, replace/remove controls and a required confirmation that all document details/the face are clear. It then shows upload progress and uploaded/ready status. Selected photos must be uploaded or removed before submitting the identity operation. Size/resolution checks cannot establish semantic readability or detect blur: the applicant must reject unclear previews and the administrator must inspect evidence before approval. No OCR or claim of automatic readability detection is made. Removing a photo unlinks the draft; it does not delete an already-uploaded immutable object.

**Platforms:** no dart:io or native compression plugin is used. Flutter compute runs the pure Dart preparation in an isolate on native platforms; on web it runs locally on the UI thread and may briefly pause interaction. The preparing indicator paints first; byte/pixel limits bound input. Android is the primary verification target. The file picker does not add a camera capture flow: take a photo through the device camera, then choose it. iOS HEIC must be exported as JPEG/PNG first. Web authenticated getData requires bucket CORS configured for the application's actual origins; do not grant public bucket access. Package resolution, platform builds, picker behavior, browser memory/performance and the existing firebase_core_web override compatibility remain unverified.

**Private objects and metadata:** DriverEvidenceService uploads only the prepared JPEG to driver_evidence/{ownerUid}/{expectedRevision}/{nic|driving_licence|selfie}/{random32hex}.jpg. It supplies ownerUid, applicationRevision, evidenceType, width and height as custom metadata and requests private/no-store caching. Filenames shown locally are sanitized; original filenames are deliberately not persisted. Reviews use authenticated, size-bounded getData and in-memory previews, never getDownloadURL or arbitrary supplied URLs. Preview routes close when their owning gated panel is removed. Normal profiles, lists and support/trip records gain no identity images or paths.

The optional evidence map in submit_identity contains only storage paths. The existing worker reads object metadata from its default configured bucket and checks exact owner/revision/type/path, actual Storage content type and size, dimension metadata and creation timestamp before the existing revision-checked transaction. It records an allowlist of storagePath, evidenceType, mimeType, compressedSizeBytes, width, height, uploadedAt, applicationRevision and generation in the private current verification and immutable submission history. No binary, download token, client timestamp or filename is put in Firestore. Metadata lookup failure fails the operation safely; refresh before retrying. Dimensions are bounded client metadata, not a trusted server image decode. Neither MIME checks nor Storage rules can prove binary readability/content authenticity; the official client decodes/re-encodes and admin review remains required.

**Rules and backend:** new storage.rules, referenced in firebase.json, permits only an authenticated driver to create a new object in their own current revision path while not verified. JPEG MIME, positive capped size, evidence type/name and matching metadata/dimension bounds are required. Objects cannot be overwritten or deleted by any client, including admins; bucket listing is denied. Only the owner and admin:true may get known evidence paths; supportAdmin alone has no access. All other Storage paths default deny. Review/merge any existing deployed bucket policy before replacing it, since no previous Storage rules file was present in this repository. The only Firestore permission extension is a bounded evidence-path map on the existing owner submit_identity operation; no direct verification, profile, history or registry writes are allowed.

The trigger needs storage.objects.get for the evidence bucket/prefix. Enable the Storage rules service agent's Firestore access when configuring cross-service rules. Ensure Flutter and the worker use the same default bucket. Deploy the reviewed worker, Firestore and Storage rules together before releasing upload UI. No deployment or IAM/bucket/CORS change was performed. Uploads and Firestore operations cannot form one cross-product transaction: canceled/replaced uploads, stale revisions, failed submissions or navigation during upload can leave unreferenced private objects. Configure an audited trusted reconciliation/retention procedure that checks pending operations and immutable submission references before deletion; no unsafe blanket bucket TTL or client delete permission is added here.

Coverage added: codec limits/type/metadata stripping, cross-owner and support-only rejection, private admin reads, nested operation retry equality, preparation/upload errors, confirmation/progress/ready UI, preview disposal, worker metadata validation and revision-safe private history. These tests are source additions only and have not run. Real Storage/Firestore rules, IAM/CORS, platform builds and live device readability checks remain pending in the manual verification document.


## Final Stage 11D registration application architecture

Source implementation is present; dependency resolution, compilation, tests, rules validation and live end-to-end verification remain pending. This section is the current behavior for NEW accounts. Earlier number-only sections apply solely to legacy profiles without registrationStatus.

### Unified flow and approval boundary

RegistrationScreen retains one Tourist/Driver role selector and basic/vehicle information form. Creating Firebase Auth credentials and the initial profile creates a draft application account (registrationStatus draft, accountStatus pending_approval, applicationRevision 0). Auth creation is NOT approval. Login resumes an existing application; an Auth account missing its profile can resume profile creation rather than create another Auth identity.

RegistrationApplicationScreen/RegistrationApplicationPanel complete the same role-aware flow: permitted profile fields, private identity numbers, required compressed photos, Guidelines & Agreement 1.0, review confirmation, then submit_application. Tourist requires NIC and NIC image/selfie. Driver additionally requires Driving Licence number/image and vehicle/operating-area information. Account type and login email cannot be changed in correction forms. Raw numbers do not enter users or public profiles.

States are draft → pending_review → approved, correction_required or rejected. Both rejected and correction_required currently permit correction/resubmission; there is no permanent-rejection flag. Successful submission sets accountStatus pending_approval independently of registrationStatus. The legacy status:active field exists for compatibility and does not authorize a new applicant.

Approved Tourist becomes accountStatus active. Approved Driver becomes identity verified but remains pending_approval until the existing verified-payment/membership activation transaction activates the account. Existing quote entitlements, founding cutoff, bank verification and renewal terms are unchanged.

### Trusted operations, uniqueness and history

RegistrationApplicationService creates immutable requests in users/{uid}/application_operations/{operationId}. processRegistrationApplication is exported alongside processDriverAdministration, with the existing region, runtime principal and HMAC secret. Owners submit; only current primary admin:true may approve/reject/request_correction. supportAdmin alone cannot review applications.

The worker validates expectedRevision, current state, field allowlists, required private evidence and explicit agreement. It uses the SAME normalizeIdentity/HMAC registry namespace as driver administration. NIC claims apply across Tourist and Driver; licence claims apply to Driver. Claims, submitted revision, profile state, audit and operation result commit atomically. Concurrent duplicate applications cannot both reserve a claim. Duplicate responses contain generic existing-account/contact-support guidance, never another UID/name/contact. Prior claims remain reserved when corrected; disputed identities require trusted operator review. Approval rechecks the secret fingerprint and current identity claim ownership.

Each submission creates registration_applications/{uid}/submissions/{revision}, increments applicationRevision and records agreementVersion 1.0 plus server-generated agreementAcceptedAt. No device timestamp is trusted. The current registration_applications/{uid} document contains private submitted identity, evidence, profile snapshot and review metadata. Driver private verification mirrors this submission for the existing membership workflow.

Each successful transition appends registration_applications/{uid}/history/{operationId} and users/{uid}/admin_history/application_{operationId}: actor, action, reason, previous/new state, revision, operationId and server timestamp. Reject/correction requires a nonempty safe reason. Submitted revisions and audit are immutable to clients; reviews never overwrite submitted snapshots. The panel pages history (20, createdAt/document ID descending) and opens immutable revisions, including their evidence and agreement. Latest 20 operation outcomes are shown; failed operations can be explicitly retried with a fresh ID, while uncertain outcomes require refresh. Replayed successful requests do not create another revision or audit. Stale expectedRevision/state fails safely.

### Operational restrictions and legacy compatibility

Pending/rejected/correction-required applicants route to application status with safe support, Account and logout access. applicationOperational guards client services; lifecycle/chat/rating checks occur inside their existing transactions. Trip posting, bidding/acceptance and other operational Firestore predicates require approved/active new accounts. New drivers additionally require identity/payment verified, active valid membership and active account. Backend lifecycle timers decline transitions for newly unapproved/inactive participants.

Profiles without registrationStatus intentionally retain legacy behavior to preserve Stage 10; no migration ran. Existing driver eligibility still applies. Historical Tourist NICs never collected/reserved cannot be inferred: before production rollout an operator must reconcile any known historical identities through trusted tooling. No client fallback claims uniqueness against unknown historical data. Generic support creation remains available to pending applicants; trip-linked operations still require participant/operational checks.

### Evidence, rules and privacy

The existing image/file-picker/Storage implementation is reused for both roles. JPEG/PNG input is normalized locally to JPEG with orientation handling and EXIF/GPS removal; quality 85 then 80 fallback. Documents: long edge ≤2000px and ≤2 MiB. Selfie: ≤1600px and ≤1.5 MiB. Clarity confirmation/manual review remains necessary; code cannot prove readability. HEIC, PDF, archives/ZIP and unsupported images are rejected. Web processing is local but may occupy the UI thread.

New paths are registration_evidence/{uid}/{nextApplicationRevision}/{type}/{random32hex}.jpg. Only the owner in draft/correction_required/rejected may create an immutable object for the next revision. Tourist cannot upload licence evidence. Known-path gets are owner/primary admin only; listing, overwrite and delete are denied. Legacy driver_evidence paths stay separate and cannot bypass new applications. The worker reads Storage metadata before attaching an allowlist (path/type/MIME/size/dimensions/upload time/generation/revision) to private snapshots. No raw binary, original filename or download-token URL is stored.

Firestore permits narrowly shaped operation creation and private owner/admin application/submission/history reads, never client application approval, identity reservations, profile privilege changes, counter or membership writes. Initial profile email must match the authenticated email; trusted status/revision defaults are fixed. Old driver identity operations cannot bypass application review. firebase.json already references storage.rules; Functions exports include the new worker. No new composite index or broad admin write permission is introduced.

public_profiles.ts remains an explicit public allowlist, excludes all identity/evidence/payment/admin/registry fields, and removes projections for newly unapproved/inactive accounts. Existing legacy projections are not bulk migrated.

### Dependency decision and outstanding work

firebase_storage is pinned to **13.4.5**, the first stable cached release whose core-platform-interface constraint is compatible with the intentional firebase_core_web 3.10.0 override. Earlier 13.4.x releases require the previous interface major. Existing firebase_core constraint permits the required core release. Other Firebase declarations and the override are unchanged; pubspec.lock was not manually edited. The actual resolver/platform build remains pending.

Focused source tests cover both role forms/submission, agreement and document requirements, pending/approved eligibility, private admin review and small/wide layouts; backend tests cover cross-role/concurrent identity claims, safe errors, revisions/audit, approval authorization and payment separation. Additional approval-claim/retry coverage and the original registration widget expectation were updated. None was executed.

Deployment requires the new application worker plus updated driver worker, lifecycle/public-profile Functions, coordinated Firestore/Storage rules and application release. Reuse the existing stable HMAC secret/fingerprint; do not rotate it or reset registry/counter. Bucket IAM/CORS, rules negative tests, package resolution, Stage 10/11A–D regressions and Android/web checks remain pending. Orphan evidence retention/cleanup, historical identity reconciliation, legal review of guidelines and operational rollout coordination remain operator work. No cleanup job, migration, renewal automation, payment gateway, email/push or broader admin features were added.


## Stage 11D attention queues, payment evidence and mobile capture

This section supersedes earlier text-only payment-proof instructions. Source changes are implemented; no commands, dependency resolution, analyzer, tests, builds, emulator checks or deployments were executed for this correction.

### Data responsibilities and drift prevention

| Location | Responsibility |
| --- | --- |
| users/{uid} | Authoritative CURRENT accountType, registrationStatus, accountStatus, identityVerificationStatus, paymentStatus, membershipStatus, membershipPlan, driverAdminRevision and other operational fields. Routing, eligibility and queue membership use this state. |
| registration_applications/{uid} | Current application REVIEW record, private submitted identity/evidence and reviewer information. Immutable submissions/{revision} hold the exact profile/identity/evidence/agreement snapshot; history preserves decisions/reasons. Its review status is updated with users in the same trusted transaction, never independently by clients. |
| driver_verifications/{uid} | Driver-specific verification workflow, evidence/review details and immutable submitted versions. It is not a second source of account eligibility. New mirrors call the application-state snapshot submittedRegistrationStatus; older registrationStatus values here are historical and ignored for routing. |
| users/{uid}/payments/{paymentId} | Existing canonical payment quote/claim/review records. They are not copied into driver_verifications. Verified payment history and quote entitlements remain immutable. |
| users/{uid}/admin_history/{operationId} | Immutable server-created administration history. |

Identity review fields required for backend consistency are mirrored atomically with current user state. Client authorization never uses a submitted profile snapshot as the operational account. The legacy owner identity display now also takes current identity status from users. No registry, fee, claim, counter or membership authority moved into Flutter.

New submissions atomically write applicationSubmittedAt on users for safe queue display; the immutable submittedAt remains on the private submission. Historical users missing the new field show Not available; there is no fabricated date or migration. Driver application approval initializes absent paymentStatus/membershipStatus to pending, retaining any existing trusted values and pending_approval account status.

### Dashboard attention queues

Pending Registrations is a dedicated dashboard section, with an identity-attention count and a separate Payment Pending count plus activation count. Identity filters: All, Tourists, Drivers, Correction Required. They query users registrationStatus in pending_review/correction_required/rejected; all current rejected applications permit follow-up. Drafts are not counted as submitted applications.

Payment Pending queries approved Drivers with pending/rejected payment, pending_approval account, or pending membership. This wider list includes retry and activation work; its payment badge counts exactly approved Driver + paymentStatus pending. The separate activation count is approved Driver + verified payment + pending membership. Approved Tourists leave identity queues; approved Drivers enter payment/membership work. Counts are server aggregations, independently consistent, explicitly refreshable and refreshed after returning from detail; they are not live subscriptions.

Pages are bounded at 30 accounts, ordered by document ID with a cursor. This includes older profiles without submitted dates. Rows retain only safe AdminUserSummary fields, submitted time and revision; no raw NIC/DL/evidence is rendered. Existing primary-admin gates plus before/after service claim checks apply. Errors/retry, stale generation protection, empty states and pagination are provided. Composite users indexes are included and need deployment/live confirmation.

Rows open the existing protected detail. Payment rows present driver payment/membership first. After application actions, detail reloads authoritative account state and its workflow panels. Existing stats, support preview, Users & Drivers and Support & Complaints entries remain.

Admin labels now prioritize registration state over legacy status: DRAFT, PENDING APPROVAL, CORRECTION REQUIRED, REJECTED, or AWAITING PAYMENT / MEMBERSHIP. ACTIVE requires the applicable current state; suspended/inactive remain explicit, and annual expiry is checked through existing driverCanBid. Display changes do not rewrite legacy status.

### Driver flow and payment proof

Pending Registration → identity/application approval → Payment Pending → manual payment verification → membership activation → Operational Driver.

Approved Drivers receive the explicit not-active-yet instruction and stay in the verification route until registration/identity/payment/membership/account conditions pass (including existing annual validity). Payment verification alone does not route to the Driver Dashboard.

The existing image component handles payment slips: JPEG/PNG input, locally normalized JPEG, 2000px maximum long edge, 2 MiB maximum output, quality 85 then 80 fallback. Preview, readability confirmation, separate Upload, progress, replace/remove and ready state are required before the claim button enables. The claim dialog collects amount/date/bank reference/depositor; the slip path comes only from successful upload, not a free-text field.

Objects use payment_evidence/{uid}/{paymentId}/{random32hex}.jpg with ownerUid/paymentId/evidenceType=payment_slip/width/height metadata. Storage permits creation only by the owner Driver for their current pending unsubmitted registration payment, with application approval where applicable. Known-path reads are owner/primary admin only. No list, overwrite or delete. JPEG, positive size ≤2 MiB, dimensions 400–2000 and exact matching metadata are enforced. Rules do not prove readability or decode image content; the official client and manual review remain required.

The backend re-reads actual Storage metadata for submit_payment AND verify_payment, validates owner/payment/type/path/size/MIME/dimensions/time/generation, and stores only safe slipEvidence metadata in the immutable submitted claim. Review shows the existing quote/payment fields, slip status and View payment slip privately. Verify and Reject remain primary-admin-only operations; Reject now requires a nonblank reason in UI/backend (rules reject empty reasons). Activate membership appears only after current paymentStatus verified and still rechecks every activation prerequisite.

Older issued payment references are never rewritten. Previously submitted text-only claims have no trusted uploaded image and cannot be newly verified by this worker: admin must reject with a reason, then the driver requests a replacement claim preserving original entitlement and uploads proof. Old verified payments and already activated memberships are unaffected. Coordinate this policy with operators before deploying; no automatic migration or history rewrite was implemented.

### New payment references

Only NEW request_payment operations generate CTPYYMMDDXXXXXX, exactly 15 uppercase alphanumeric characters (e.g. CTP260923A7K4Q2). The server uses UTC date and cryptographically random six-character suffix from an unambiguous 32-character alphabet. The existing transactional payment_reference_registry prevents collisions; a collision fails safely and an explicit new request can retry. Firestore payment ID remains the operation ID. Replays return the existing operation result and do not change a stored reference.

### Camera source and platform setup

Added image_picker **1.2.1** for native camera capture; Firebase versions and the core-web override are unchanged and pubspec.lock is untouched. The plugin supports mobile camera selection as documented at https://pub.dev/packages/image_picker/versions/1.2.1.

Android/iOS selfie selection ALWAYS requests camera/front camera; capture cancel/failure never falls back to gallery. NIC/DL keep the existing system image selection. Mobile payment slips offer Take photo (rear camera) or Choose photo. All sources still undergo the same local processing/preview/explicit upload. Web/desktop use the existing JPEG/PNG file picker and display an explicit recent-selfie fallback explanation; no direct-camera guarantee is made there. Camera-only is a client source restriction, not biometric liveness or server attestation.

iOS camera/photo-library usage descriptions are added. Android minSdk is at least 24 for this plugin release. Native plugin registration/dependency resolution must be performed by the operator. If Android destroys the app during capture, no recovered file is automatically attached to an account/payment/revision: reopen the current workflow and retake/reselect. Automatic lost-image recovery is not implemented; process-death, permissions, real-camera formats, Android memory behavior and iOS/web builds remain manual verification.

Tests were added/updated for safe queue rows/counts, labels/operational routing, current-profile authority, payment-slip requirements, camera source selection, private path authorization, metadata rejection, admin payment/reason behavior, new reference shape and unchanged old references. Existing approval/activation tests now expect pending payment/membership initialization and hidden pre-verification activation. None was run.

Deployment: resolve the new plugin; deploy updated registration/driver workers, narrow Storage/Firestore rules and indexes; confirm bucket IAM, index readiness and mobile permissions. Reuse the existing HMAC secret, registry and counter. No client write rights were broadened for account state, no commission/per-trip fee was added, and all existing commercial entitlements are retained.

## Stage 11D live-device stabilization (source changes; verification pending)

Private evidence remains authenticated Storage byte access (getData, maximum 2 MiB), rendered from memory. The viewer now force-refreshes the Firebase Auth token before checking primary-admin claims and fetching the object. It reports denied access, expired session, missing object, network failure, invalid reference and size-limit errors separately, and discards late previews after owner changes/disposal. No download URLs or Storage permission changes were introduced. Cached claims were a concrete client weakness; the exact live Storage failure still requires confirmation with the new error category.

Android/iOS NIC, Driving Licence and payment-slip controls offer camera and gallery via image_picker. Selfie remains camera-only; web/desktop retains the documented file fallback. JPEG normalization, local preparation, preview, readability confirmation, explicit Upload, dimensions, size limits and private paths are unchanged.

Payment/admin action forms now show field-specific inline errors and the first error next to Confirm, including depositor, amount, date, transaction reference and mandatory rejection reason. Missing payment-slip upload is explained inline. Registration validation scrolls to the first invalid form field. Approved-driver status text distinguishes payment review from waiting for membership activation. Session routing already keeps authenticated non-operational drivers in the registration screen; those gates are unchanged. Admin summaries distinguish registration, identity, payment, membership and account; account buttons explicitly say Set account. No duplicate identity approval was added.

Lifecycle source review found no scheduled-start-time restriction: the accepted assigned operational driver can request start even before the scheduled time. The two transactions still publish a server-time anchor followed by the exact parent transition; the 60-second anchor freshness rule, 3-minute start and 30-minute end confirmation windows and Stage 10 backend remain unchanged. Missing/invalid anchors now produce a state error. UI errors preserve state errors and distinguish permission denial, authentication, connection and concurrent/precondition failures. No proven static payload/rule mismatch was found; the reported live start failure is NOT claimed resolved and requires the actual new error category and deployed-rule check.

Private chat unread dots appear on assigned trip cards and the trip detail chat entry. Each listener fetches only the latest incoming message for the current assignment (assignmentDriverId + senderId equality, createdAt descending, limit 1), plus the recipient's own trip_posts/{tripId}/chat_reads/{uid} document. Read cursors store assignmentDriverId, lastReadMessageId, the immutable message's lastReadAt timestamp and server updatedAt. Opening/receiving messages while the chat is foreground/current acknowledges only an incoming displayed message; own messages do not advance the cursor. Transaction checks prevent stale assignment writes and backwards cursor movement across devices. No message content is copied into read records; historical messages remain immutable. Rules permit only current participants to read/write their own cursor, validate its referenced incoming message, and deny list/delete/other-user access. A COLLECTION messages composite index (assignmentDriverId ASC, senderId ASC, createdAt DESC) was added.

FCM is deferred: the project has no messaging/token/delivery foundation. A later stage needs platform FCM configuration and permission handling, private owner-scoped token registration/rotation/removal, a trusted idempotent message-create sender that rechecks assignment/recipient eligibility, generic privacy-preserving notification text, and deep links that reauthorize on open. Sound follows device/app settings. No fake local, push or email notification was added.
