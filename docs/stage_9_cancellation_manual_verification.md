# Stage 9: accepted trip cancellation

## Follow-up: creator withdrawal before acceptance

Creators can now cancel `open` as well as `accepted` trips from View Bids,
including when no bids exist. Both creator flows first show a modal warning with
the permanent-closure wording and a warning icon. Only **I Understand - Continue**
opens the reason form; **Keep Trip**, back dismissal, or any other result cannot
proceed. Saving and final confirmation protection remain in the reason form.
Open-trip success returns through trip details to the creator list/home.

The new service branch checks the stored owner, active profile, open status and
null acceptance IDs. It reads no bids and atomically writes only the parent and
history. History uses the creator UID as deterministic ID: creators cannot bid on
their own trip, so that UID cannot collide with accepted-bid history. An open
withdrawal is terminal and occurs at most once. This also works after earlier
accepted-driver cancellations reopened the post.

Open history retains the exact existing schema, with `cancelledByRole: creator`,
`previousStatus: open`, `resultingStatus: cancelled`, `penaltyApplied: false`, and
server timestamps. The parent changes only status, last cancellation actor/reason/
timestamp, and updatedAt. Acceptance IDs remain null; count and exclusions remain
unchanged, including fields absent in old Stage 8 documents.

`cancellationCount` historically counts accepted-trip cancellation events, including
those without penalties; it is not a penalty-only count. This follow-up preserves
that behavior and does not increment it for unassigned withdrawals. Consequently,
it is not a count of all history documents. Do not use it as a cancellation-rate
denominator or silently change its meaning.

The separate `open -> cancelled` rule requires creator ownership, the exact five
changed fields, request-time timestamps and reciprocal immutable history creation.
It cannot change trip details, exclusions, counts or acceptance IDs. Existing
accepted-trip cancellation and Stage 8 acceptance checks are retained. Submitted
bids remain byte-for-byte unchanged; the existing effective status displays them
as TRIP CANCELLED and disables acceptance under the cancelled parent.

Additional manual checks (not executed):

- Tourist and partner creator withdrawal with zero bids and multiple submitted
  bids; verify no bid changes, no penalty even near/past schedule, same parent ID,
  preserved counts/exclusions, and immutable creator-UID history.
- First-warning ordering, Keep Trip, outside tap, Continue, reason validation,
  saving state and return to list/home; repeat for accepted creator cancellation.
- Verify rules compile and reject parent-only/history-only writes, wrong owner,
  forged penalties/reasons/timestamps, count/exclusion/detail changes, terminal
  cancellation and driver attempts to withdraw another creator's open trip.
- Race withdrawal against acceptance and bid submission: inspect the final stored
  state, no actionable bids after cancellation, and correct accepted/open history
  based on the transaction's stored state. The dialog warning is a time/state
  preview; the stored state is authoritative.
- Repeat Driver 1/Driver 2 bidding, Driver 1 acceptance/cancellation, same-post
  reopen, Driver 1 exclusion, Driver 2 previous-bid acceptance, then creator
  cancellation. Also withdraw a reopened post before accepting Driver 2.
- Review the new in-memory service transaction tests and updated widget tests.
  They were added without execution; no Firebase integration tests were added.

Implementation only. Tests, analysis, builds, Git operations and Firebase deployment were not run.

## Data and atomic writes

New trip posts initialize `excludedDriverIds: []`, `cancellationCount: 0`,
`lastCancellationBy: null`, `lastCancellationReason: null`, and
`lastCancellationAt: null`. Existing Stage 8 documents read with these defaults;
the first cancellation adds the fields. Acceptance still changes only its original
four fields and does not require migrated documents.

History lives at `trip_posts/{tripId}/cancellations/{acceptedBidId}`. This deterministic
ID is resolved from the stored accepted bid within the transaction. It is unique
per cancellation because UID bids are create-only and a cancelled bid can never
be accepted again. No extra parent pointer or new trip document is needed.

Each record contains exactly: `id`, `tripId`, `cancelledByUid`, `cancelledByRole`,
`reasonCode`, `reasonText`, `penaltyApplied`, `previousStatus`, `resultingStatus`,
`cancelledAt`. Roles are `creator`/`driver`; previous status is `accepted`.

Both explicit service APIs read the active user's profile, parent and accepted
bid in a transaction, recheck the session, and write parent, bid and history
atomically. Creator identity is determined by UID ownership, including partner
creators. Driver cancellation reopens the same parent, clears acceptance, appends
the driver to exclusions, and sets the bid to `cancelled`. Creator cancellation
closes the parent as `cancelled`, clears acceptance and sets the accepted bid to
`trip_cancelled`. Both increment parent cancellationCount exactly once and save
the actor, display reason and timestamps. Other bids are untouched.

Rules require reciprocal before/after parent, bid and history consistency, exact
changed-field lists, exact history schema, role-specific reasons, trimmed details,
and request-time timestamps. History cannot be updated or deleted. The creator
can read their history; a driver can read their own cancellation or the creator
cancellation whose history ID identifies that driver's assignment. History is
not globally readable. Existing acceptance validation remains intact.

## Authoritative penalty handling

`scheduledAt - request.time < duration.value(2, 'h')` means penalty; exactly two
hours means no penalty. All persisted timestamps use server transforms.

Firestore clients cannot write a boolean computed from a server timestamp
transform. The service first proposes `penaltyApplied: false`; if rules reject
with permission-denied, it retries the entire transaction once with `true`.
Rules accept only the flag matching that write's request time. This avoids relying
on device clocks, including near-boundary latency. A rejected attempt writes
nothing. The second attempt repeats every identity/state check and cannot bypass
authorization. Other errors are not retried by this fallback. Within-two-hour
cancellations normally incur one rejected attempt and a second network round trip.
Manual verification must include both paths and concurrency. The UI time warning
is a preview; final penalty is determined at save time.

`cancelledTripsCount` updates are deferred: user profile updates remain denied,
and no additional client metric-writing privileges were introduced. The immutable
penalty flag is the audit source for a future trusted, idempotent aggregation.
No cancellation fees, fines, ratings writes or automatic star changes are added.
Do not calculate cancellationRate until sufficient recent trip history exists.

## UI and bidding

The accepted driver's own-bid screen offers Cancel Trip. The creator's View Bids
screen offers Cancel Trip for accepted trips, for both tourist and partner
creators. The shared dialog requires a suggested reason, requires details for
Other, trims details, limits them to 500 characters, shows the appropriate closure
or reopen warning and penalty preview, disables actions while saving, and keeps
errors in the dialog for retry. Successful driver cancellation returns to the
previous screen; successful creator cancellation shows the live closed trip.

The open feed filters excluded drivers locally. Bid creation also checks stored
exclusions in the service and rules. The original cancelled UID bid remains.
Submitted losing bids remain submitted in storage and become selectable on reopen;
explicit cancelled labels survive subsequent acceptance of a different bid.
Creator-cancelled trips leave open feeds and accepted-driver assignments.
Existing future-schedule filtering/acceptance constraints remain: reopening a
past-scheduled trip does not make its expired schedule eligible for bidding.

Notifications, including notification when a previous submitted bid is reselected,
are deferred. No FCM, contacts, start/end trip, payment or admin upgrade work added.

## Manual verification checklist

1. Review/validate the rules in your chosen Firebase workflow before enabling the
   feature. Rules compilation and access-call limits have not been executed here.
   Cancellation requires the updated rules; current live Stage 8 rules reject it.
2. Create a new tourist trip and partner trip; inspect all five initialized fields.
   Also accept/cancel an existing Stage 8 trip missing those fields.
3. With drivers A/B submitting bids, accept A. Cancel as A with a normal reason.
   Verify same trip ID, open state, cleared acceptance, A excluded, count +1,
   three matching server timestamps, one immutable record, A's cancelled bid and
   B's unchanged submitted bid. A's accepted assignment disappears.
4. In the creator's still-open bid list, accept B's previous bid. Confirm A remains
   labelled CANCELLED. Repeat driver cancellation to verify accumulated exclusions
   and separate history records. Submit a new eligible driver's bid in real time.
5. Verify A cannot rebid via UI or a direct client write, and cannot overwrite or
   delete their old bid. Other eligible drivers still see the reopened trip.
6. Cancel as tourist creator and partner creator. Verify permanent cancelled state,
   `trip_cancelled` accepted bid, preserved history, no feed/assignment entry and
   no reopening or bid creation. Creating transport again requires a new post.
7. Verify >2 hours, <2 hours, exactly 2 hours (rules request time), past schedules,
   device clock skew and crossing the boundary while the dialog is open. Inspect
   persisted penalty flags rather than relying on UI previews.
8. Check missing reason, Other with whitespace only, 500/501 characters, multiline
   details, Keep Trip, saving spinner, repeated taps, network failures and retry.
9. Attempt unauthorized actor/inactive user cancellation, wrong role/reason,
   forged penalty/timestamps/count/exclusions, parent-only or bid-only updates,
   history-only creates, extra fields, history edits/deletes and unrelated reads.
   All must fail. Confirm original bid acceptance remains atomic/private.
10. Race driver versus creator cancellation and duplicate clients. Only one
    transition/history/count increment may succeed; stale attempts must fail.
11. Manually review the added focused tests, including schema, legacy defaults,
    penalty boundary, reasons, bid effective status and dialog saving behavior.
    Run them yourself when ready; no Firebase integration tests were added.
