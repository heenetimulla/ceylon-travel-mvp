# Stage 11A and 11B manual verification

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

Stage 11B adds only Users & Drivers browsing and read-only details. No deletion, moderation, verification actions, role upgrades, full support inbox or reporting controls should appear.

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
