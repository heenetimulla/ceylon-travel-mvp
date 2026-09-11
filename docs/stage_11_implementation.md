# Stage 11A: secure admin foundation and overview

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

**Important privilege boundary:** Firestore rules cannot distinguish an aggregate count from a document-list query. The trusted admin claim therefore permits listing complete private user/trip/support parent documents, not only counts or the five UI preview rows. The Flutter UI retrieves only aggregates plus five requests, but this is not a security cap on trusted admins. Normal users do not gain these permissions. If a future staff role must receive totals only, implement a trusted aggregate/projection endpoint before granting that role access; do not grant this primary-admin claim. No broad wildcard admin rule was introduced, and `canGetTripPost` was not expanded (chat relies on it).

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

Deferred: individual account/driver management, verification, support inbox/actions, staff roles, destructive operations, analytics, reports, payments and every other later Stage 11 feature. Stage 10 production services, Functions/Cloud Tasks, chat assignment privacy, location, ratings, support writes and theme are unchanged.
