# Stage 11: admin foundation, account management and support inbox

Implementation only; tests, analyzer, builds, package commands, Firebase and Git were not run.

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
