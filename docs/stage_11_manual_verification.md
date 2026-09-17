# Stage 11A, 11B and 11C manual verification

All checks are for the operator. Codex did not execute tests, analyzer, builds, Firebase commands, npm, package changes or Git commands.

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
