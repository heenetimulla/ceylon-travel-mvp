# Stage 11A manual verification

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

No management, deletion, moderation, verification, role-upgrade, full support inbox or reporting controls should appear in the Stage 11A dashboard.
