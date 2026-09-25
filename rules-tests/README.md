# Lifecycle Firestore Rules regression

This isolated Node test package exercises the actual repository firestore.rules with authenticated Firebase client writes against the Firestore emulator. It does not use mocked authorization or Admin SDK lifecycle writes. Rules-disabled access is used only to seed/reset fixtures (including expired/future anchors without sleeping). Flutter and Functions dependency manifests/locks are unchanged.

No installation, emulator, test or deployment was run when these source changes were made. Install the pinned test-only dependencies and generate/review package-lock.json before using this suite in CI; no lockfile was handwritten. Node 22, Firebase CLI and its supported Java runtime are manual prerequisites.

Manual setup:

1. In rules-tests, install the dependencies from package.json.
2. Start only the Firestore emulator using rules-tests/firebase.json and project demo-ceylon-lifecycle-rules. This config has no Functions or Auth emulator and no production project.
3. Set FIRESTORE_EMULATOR_HOST to 127.0.0.1:8080 for the test process. The suite requires an explicit loopback endpoint and hardcodes the demo project; it will not silently fall back to production.
4. Run this package's test script. No TypeScript build is needed. The suite loads ../firestore.rules itself and runs serially because it clears only its demo project's emulator data between tests.
5. Inspect the fresh emulator output/debug log even when every test passes. Search for "maximum of 1000 expressions" (case-insensitive). Any occurrence during lifecycle parent-update tests fails verification: permission-denied alone does not prove predicate-based rejection. Use a fresh log/session or inspect only output from this run, not warnings retained from the previous run.
6. After tests pass, deploy only the reviewed root firestore.rules through the normal release workflow and repeat the live two-transaction start flow. No Flutter release, Functions deployment, timing change or new index is required by this correction.

Coverage includes founding/annual approved drivers, a future scheduled trip, registration/payment/identity/account/membership denials, expired/missing annual validity, wrong driver, unaccepted trip, missing/wrong-actor anchor, exact request timestamp and three-minute deadline, fresh versus older-than-60-second/future anchors, unrelated-field tampering, and legacy driver compatibility. The successful path mirrors both Flutter transactions and asserts stored seconds/nanoseconds are preserved. Negative parent writes are attempted directly so a denied preliminary read cannot hide missing parent-write protection.

## Exclusive state-transition dispatch correction

The latest reported emulator run had 43 tests: 4 passed and 39 failed because strict denial assertions detected evaluator exhaustion. The previous OR-based shape routing was therefore insufficient; the earlier assertion that it prevented all unrelated evaluation was not validated by the emulator.

The parent update now calls one validTripParentUpdate dispatcher. Nested Firestore Rules conditional (ternary) expressions select exactly one complete validator using only current status and requested status:

- accepted -> start_requested, start_requested -> in_progress, in_progress -> end_requested, end_requested -> completed: validLifecycleUpdate.
- open -> accepted: validTripAcceptance.
- accepted -> open/cancelled: validCancellation.
- open -> cancelled: validOpenCreatorCancellation.
- All other transitions: false immediately, without invoking any full validator.

The router does not inspect affectedKeys. An accepted -> start_requested request containing a malicious notes/assignment change still goes only to validLifecycleUpdate, whose existing exact allowlists reject it. A selected validator returning false is the final result, not a signal to attempt other validators. The old four shape helpers and their OR dispatcher were removed; no authorization predicate was removed.

The overlapping recursive match at the end of firestore.rules remains allow read, write: if false. It contains no helper calls or document lookups, does not duplicate the expensive parent validation, and was not changed. Its location in a denial diagnostic is not itself proof of expensive duplicate evaluation.

The complete existing 43-test suite is unchanged, including assertDenied's permission-denied check and rejection of evaluator-exhaustion diagnostics. Profile predicates, legacy handling, all full validators, identity/payment/membership gates, timestamps/deadlines, reciprocal bid/history/profile writes and excluded-driver behavior are unchanged. No Flutter, Functions, index, dependency or test changes accompany this correction.

No commands or tests were run for this correction. Verification still requires 43 passed, 0 failed AND no 'maximum of 1000 expressions' warning in fresh emulator output for parent update tests. The SDK may expose only a generic denial while the emulator logs its real cause separately, so step 5 remains mandatory. A clean result is a target, not a verified outcome.
