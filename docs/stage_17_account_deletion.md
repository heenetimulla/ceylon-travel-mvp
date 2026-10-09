# Stage 17A — Account deletion request flow

**Stage 17A: IMPLEMENTED — VERIFICATION PENDING**

Source-only implementation. No commands, subprocesses, Flutter, npm, tests, builds,
Git, Firebase CLI, gcloud, deployments, emulator, device or browser were run for
this stage. The supplied branch/checkpoint/green CI were not independently checked.
Generated JavaScript under functions/lib is intentionally untouched.

## Scope and launch decision

This is a reviewed, staged deletion workflow, not instant client hard deletion.
The app must not claim all personal data is automatically erased on approval.
Launch still requires an operational cleanup owner, a reviewed retention policy,
a working external deletion-request page/URL, and a privacy policy matching the
behavior below. No statutory retention duration is assumed or invented here.

## User flow

Account & Support and Profile & Account Settings expose **Delete Account**.
The legacy restricted driver screen now links to Account & Support too.
Unapproved registration accounts already have that route.

The screen explains request/review delays, possible retention/anonymization of
shared trip/review/payment/audit records, loss of access after approval, and the
difference from logout. An explicit checkbox and current password are required.
The existing AuthService reauthentication helper refreshes the ID token; rules
independently require a non-future auth_time within five minutes.

Submitting creates a single UID-keyed request using a Firestore transaction.
Pending/approved/completed requests cannot be resubmitted. Rejected or
needs_clarification requests may be returned to pending with an optional reason
or clarification and an incremented revision. No cancellation flow was added.
No extra identity documents are requested.

The page streams status and an explicitly user-facing review message.
Private review notes and cleanup records are never included in this document.
While pending, rejected or awaiting clarification, existing account eligibility
is unchanged. On approval, access is blocked and Auth is disabled/revoked.
A still-valid existing session may fetch only its own request status; it cannot
perform normal reads/writes. Once the Auth session expires or Auth is deleted,
the user cannot sign in to view completed status. The UI discloses this; define
a verified off-app support follow-up procedure before launch. This stage adds
neither account recovery nor a new public status endpoint.

## Request and authority model

Path: account_deletion_requests/{uid}. Missing document means not_requested.

| Field | Authority / meaning |
| --- | --- |
| requesterUid | Exactly the authenticated owner UID |
| requestedAt | Original request server timestamp, preserved on resubmission |
| status | pending, needs_clarification, approved, rejected, completed |
| reason | Optional owner text, maximum 500 characters; erased at completion |
| updatedAt | Server timestamp |
| revision | Starts at 1; incremented on resubmission/review; stale review fails |
| reviewedBy / reviewedAt | Trusted worker sets reviewer UID and timestamp |
| completionAt | Trusted worker only, after cleanup clearance and Auth deletion |
| processingStage | null, restricting_access, manual_cleanup_required, completing, completed |
| userMessage | Deliberately public-to-owner explanation, separate from private notes |

Child collections:

- operations/{operationId}: primary admin creates an immutable command with
  actorUid, action, expectedRevision, note, userMessage, status=pending, createdAt.
  Backend owns processing/succeeded/failed results and timestamps. Owner and
  support-only users cannot read these commands or submit them.
- audit/{operationId}: backend decision metadata. The _processed event records
  completion of external side effects. No request reason/evidence is copied here.
- private/membership: minimal snapshot of membership terms, amounts, registration
  number and payment link, captured before replacing the profile.
- private/cleanup: trusted operator clearance described below. No client, including
  the primary-admin Flutter UI, may write it.

account_deletion_blocks/{uid} is a backend-only durable access barrier. Keep it
and the minimal deleted profile when cleaning up. Removing the barrier or restoring
the entire profile is not a supported recovery action.

## Admin flow

Existing Admin Dashboard -> Account deletion requests. Queue filters by status
and pages 30 accounts at a time. Summary cards show only UID and status.
Detail shows request date, status and user-supplied reason, without identity images,
contact details or financial evidence.

Primary admin (existing admin custom claim) may approve, reject, request
clarification or request completion. SupportAdmin alone has no deletion authority.
A requester cannot approve their own account even if they have an admin claim.
Staff accounts must first have privileges removed by the existing trusted staff
process and be reviewed by another primary administrator.

Review actions require explicit confirmation. Rejection and clarification require
a separate message to the requester. A private admin note is not copied into that
message. Backend rechecks live Auth admin/disabled state, request revision and
target staff claims, rather than trusting Flutter or an old claim on its own.

## Trusted processing and failure behavior

processAccountDeletion follows the existing immutable Firestore operation worker
architecture. Configure ACCOUNT_DELETION_REGION (default asia-southeast1) and a
dedicated ACCOUNT_DELETION_SERVICE_ACCOUNT before eventual deployment. Grant only
the required Auth lookup/update/revoke/delete and Firestore access. This automated
worker does not need Storage deletion permission; evidence cleanup is a separate
trusted operator responsibility. Do not repurpose the existing driver/lifecycle
runtime account without an IAM review.

Approval checks current trip_posts for creatorId, acceptedDriverId, touristId and
driverId with status open, accepted, start_requested, in_progress or end_requested.
It fails while any such trip exists. Resolve these through existing operational
procedures before approval; do not strand another participant. Composite query
indexes are included in source but have not been deployed.

A transaction records authorization, audit, a permanent access block and
non-operational profile state. Then the trusted worker:

1. Disables Auth and revokes refresh tokens.
2. Removes all users/{uid}/fcm_tokens and notification_staff/{uid}.
3. Removes the user's public profile and its projected review children.
4. Replaces only the users/{uid} parent with a minimal deleted profile:
   generic name, empty contact fields, no photo/vehicle/evidence/current private
   fields, disabled eligibility and numeric historical reputation counters.
   Subcollections are deliberately NOT cascaded.
5. Leaves status approved / manual_cleanup_required, never completed.

Transport/Auth/Firestore failures leave a durable processing job retryable.
No completed marker is written before the external effects succeed.
Duplicate delivery checks operation status and does not repeat business decisions.
Once a decision commits, its job remains authorized to finish even if that admin
later loses their role; new decisions still require current authorization.
Operator monitoring/replay for exhausted platform retries must be established.

Completion requires a current trusted cleanup clearance and another primary admin
operation. It rechecks absence of active trips, repeats idempotent access/token/
projection cleanup, deletes Firebase Auth (already absent is treated as success),
writes the completed state and trusted completion audit, and erases the request
reason, public explanation and completion-command note. Completion is irreversible.
No client deletes Auth, protected collections or evidence.

## Actual UID-linked data inventory and cleanup policy

This review uses source paths, not a production-data inventory. The older
firebase-data-plan mentions a separate trips collection, but current implemented
trip workflows use trip_posts. Any legacy trips or unmodeled exports encountered
in production require operator inventory; no guessed cascade is included.

| Category / implemented location | Automatic behavior | Required reviewed disposition |
| --- | --- | --- |
| Auth user | Disabled/revoked on approval, deleted at completion | Confirm no staff claims remain; existing account cannot log in |
| users/{uid} | Parent replaced with minimal non-operational tombstone; numeric counters retained | UID and counters support shared-history consistency; review minimization without breaking counterpart records |
| users/{uid}/fcm_tokens; notification_staff/{uid} | Deleted on approval and completion | Existing push infrastructure also skips blocked recipients; an already in-flight push cannot be recalled |
| user_public_profiles/{uid}/reviews | Profile and projections deleted | Original shared ratings remain subject to separate review |
| user_reputation/{uid} | Not cascaded; public numeric metrics only | Preserve minimal numeric consistency for other participant rating/history; review future linkage/minimization |
| trip_posts/{id} | No automatic deletion or rewrite | Review creatorName, pickup/drop text, notes, cancellation reasons and identifiers; de-identify requester fields where feasible without changing the other participant's facts |
| trip_posts/{id}/bids/{id} | Not deleted | Review driverId, driverName, vehicle/contact-like free text, message and pricing; protect other bidders' data |
| trip_posts/{id}/messages/{id}, chat_reads, lifecycle_requests, cancellations | Not deleted | Review sender IDs, message text and shared location coordinates, read cursors and cancellation data; remove unneeded personal content; retain only justified dispute/safety evidence |
| trip_posts/{id}/ratings/{direction} | Shared original records and counterpart numeric reputation preserved | Review ratedByUid/ratedUserUid and comments; remove/anonymize unnecessary text. Remove affected projections under other users where needed |
| support_requests/{id}, messages, status_history | Not deleted | Review userId, creatorId, acceptedDriverId, senderId, names, contactNumber and free text; retain only justified unresolved dispute/audit portions |
| registration_applications/{uid}, submissions, history | Not deleted automatically | Delete unnecessary NIC, licence, email, profile snapshots and evidence references, including reused upgrade evidence; minimize decision metadata if justified |
| driver_verifications/{uid}, submissions | Not deleted automatically | Review every revision, raw identifiers, profile copies and evidence pointers; remove unnecessary private data |
| registration_evidence/{uid}/..., driver_evidence/{uid}/... | No automatic Storage cascade | Delete unnecessary NIC/licence/selfie objects and unused uploads; check referenced immutable generations, metadata and any legacy/download-token copies |
| users/{uid}/payments/{id}; payment_evidence/{uid}/... | Financial records preserved pending review | Minimize depositor/contact/reference/slip data; preserve only necessary accounting/dispute evidence. Storage and Firestore cleanup must agree |
| Membership fields; private/membership; driver_registration_registry | Minimal terms snapshot captured; eligibility revoked | Retain only justified amounts/entitlement/registration history for accounting and dispute resolution; do not reassign an old registration number |
| identity_registry, payment_reference_registry, payment_bank_registry | Not deleted automatically | Determine justified fraud/deduplication/accounting needs for UID links/HMAC keys; pseudonymous is NOT anonymous. Decide identity reuse policy explicitly |
| users/{uid}/application_operations, driver_operations, admin_history | Not deleted automatically | Raw operation payloads may duplicate identity/contact/evidence data: scrub or remove unnecessary payloads; retain minimal actor/action/outcome metadata only when justified |
| deletion requests, operations, audit, private cleanup; account_deletion_blocks | Trusted state/audit and block retained | Minimize historical reasons/notes and policy evidence; retain only necessary completion/security proof. Preserve idempotency/result markers needed by retries |
| workflow_push_delivery, trip/message push_delivery, logs, backups, exports | No automatic external purge | Inventory indirect UID/event references and copies; apply reviewed backup/restore restrictions and expiry rather than claiming nonexistent purge |

No list above grants blanket permission to retain everything in a collection.
Pending manual review is an intermediate stage, not an indefinite retention policy.
The responsible operator must identify actual records, remove unneeded content,
de-identify shared records where feasible, record specific reasons for exceptions,
and assign review dates to retained material. Fraud, dispute, accounting, legal and
audit needs are possible rationales, not automatically applicable exemptions.
Legal and retention-policy review is required; this document is not legal advice.

## Trusted manual cleanup clearance

After approval reaches manual_cleanup_required, an authorized operator uses the
trusted administrative environment (not Flutter) to perform the inventory and
cleanup. This stage intentionally does not ship a broad wildcard deletion script.

Write account_deletion_requests/{uid}/private/cleanup only after work is done:

- requestRevision: exact current request revision.
- operatorUid: responsible operator identifier.
- completedAt: trusted Firestore Timestamp.
- policyReference: reference to the approved actual retention/privacy policy.
- categories: every category below is mandatory:
  shared_history, private_evidence, identity_and_applications,
  payments_and_membership, support_and_messages, operations_and_audit,
  backups_and_exports.
- Each category has disposition (deleted, anonymized, not_present or
  minimized_retention), recordReference (specific inventory/decision evidence),
  and rationale. minimized_retention additionally requires reviewAt, a Firestore
  Timestamp after completedAt. The referenced inventory must enumerate individual
  records, necessary fields, access restrictions and deletion/review obligations.

A blanket boolean or missing/stale category record cannot unlock completion.
The backend validates the clearance structure and revision; the operator remains
responsible for its truth and actual record-level minimization. If any needed
decision is unresolved, do not write clearance and do not complete the request.

Clear old private review notes and duplicate identity payloads as part of
operations_and_audit. Preserve minimal operation status/idempotency records and
the access barrier. Do not delete or overwrite a processing job. Do not edit the
pending completion command. An authorized completed command will erase its own
free text. Do not remove current profile counters/UID bindings until a compatible
shared-history migration is reviewed. Maintain counterpart read access and rating
consistency, then capture evidence of that review in shared_history.

Retained-object access must remain restricted to existing authorized purposes.
Decide how previously issued download tokens, device caches, exports, backups,
restored data and pending worker retries are handled. Data already downloaded by
another participant cannot be remotely erased by this worker.

## Security and existing workers

Firestore denies regular access for a blocked UID independently of stale account
fields. The only exception is an exact own-request status get. Clients cannot
remove blocks, set review/completion fields, write private cleanup, mutate audit/
financial records or delete another user. Primary admins enqueue commands; they
cannot directly change request status or write cleanup through client rules.

Existing driver/application workers read target and actor deletion barriers inside
their transactions, so queued approvals or membership actions cannot restore access.
Lifecycle workers skip blocked participants. Public projection workers check the
barrier transactionally to prevent republishing a deleted profile or affected review.
Bid acceptance cannot select a blocked performing driver.

Storage evidence reads and registration/legacy evidence uploads check the durable
barrier. Payment uploads reuse the backend-only profile deletionStatus check plus
the existing profile/payment guards, keeping the existing two-document lookup
budget. This marker is atomically set with the barrier and preserved by the minimal
profile; guarded workers cannot clear it. Full out-of-band profile replacement by
an operator could break this invariant and is prohibited. Test lookup budgets and
stale-token behavior before deployment.

No new deletion FCM notifications were added; live status is the MVP mechanism.
The existing shared push token iterator now skips blocked UIDs.

## Verification pending and operational prerequisites

No tests or compilation have run; source review does not establish runtime success.

Added test sources:

- functions/test/account_deletion.test.ts: admin authorization, active-trip
  preflight, private-field/token cleanup, protected shared/financial history,
  clearance enforcement, retry/idempotency/concurrent review, queued restore denial.
- rules-tests/account_deletion.test.mjs: own request/fresh auth, duplicate prevention,
  another-user denial, self-completion denial, support-only denial, primary admin
  command path, clarification revision, private records and stale completed access.
- rules-tests/account_deletion_storage.test.mjs: private evidence access, stale
  sessions, approved/completed upload denial.

The Firestore test source is registered in the existing rules test script;
Storage has a separate test:deletion-storage script. Neither was run.

Before launch, in a separately authorized verification stage:

1. Format/analyze/compile changed Dart and TypeScript, run appropriate existing and
   new suites, then verify real request/admin UI and interrupted network/session cases.
2. Verify Firestore multi-document lookup budgets across existing trip/rating/chat
   writes, Storage lookup budgets, query/index requirements and counterpart history.
3. Verify Auth disable/revoke/delete IAM, real retry behavior, large token/projection
   cleanup, worker monitoring, and manual cleanup authorization.
4. Verify the actual production schema, all revisions, legacy objects, shared-history
   redaction and application/payment/identity registry retention decisions.
5. Define a reviewed processing service target and escalation/appeal/support procedure,
   including access to final status after sign-in is disabled. No time promise is coded.
6. Approve policy language and data handling/backup restoration procedures.
7. Provide and verify the external web deletion-request page/URL for Play submission.
   That external URL is still required and is not implemented by Stage 17A.

Deployment, IAM changes, real account deletion, and production cleanup were not
performed. The checkpoint's existing CI status says nothing about these new edits.

## Source file inventory

Created:

- functions/src/account_deletion.ts
- functions/src/account_deletion_trigger.ts
- lib/core/services/account_deletion_service.dart
- lib/screens/auth/account_deletion_screen.dart
- lib/screens/admin/admin_deletion_requests_screen.dart
- rules-tests/account_deletion.test.mjs
- functions/test/account_deletion.test.ts
- rules-tests/account_deletion_storage.test.mjs
- docs/stage_17_account_deletion.md

Modified:

- functions/src/index.ts
- firestore.rules
- storage.rules
- firestore.indexes.json
- functions/src/driver_administration.ts
- functions/src/registration_application.ts
- functions/src/public_profiles.ts
- functions/src/lifecycle.ts
- lib/screens/auth/profile_settings_screen.dart
- lib/screens/auth/account_screen.dart
- lib/screens/admin/admin_dashboard_screen.dart
- functions/src/chat_push.ts
- lib/screens/driver/driver_registration_status_screen.dart
- rules-tests/package.json
- lib/core/services/auth_service.dart
