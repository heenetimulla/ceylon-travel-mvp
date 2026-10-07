# Stage 15 — Essential Launch UI Cleanup

Status: **IMPLEMENTED — VERIFICATION PENDING**

Baseline supplied by the developer: branch `ceylon-travel-mvp`, checkpoint `9e25e07 Fix launch-critical workflow blockers`, CI GREEN. That CI result predates this cleanup. Stage 13 runtime verification and Stage 14 verification remain pending.

## Scope and source review

This is a minimal source-only UI pass for the initial Android launch. No application redesign or new feature was introduced. No commands, tests, builds, Git operations, deployments, emulator, device or browser were run. Files were read and edited directly. Relevant local Flutter framework source was read to check chip state-color handling and dropdown sizing; Flutter was not executed.

| Screen / component reviewed | Finding and action |
| --- | --- |
| Login | Existing scrollable form retained; disabled login button now says “Signing in...”. |
| Unified registration / driver fields | Selected and unselected account choices previously shared the same pale background and had no border. Shared chip colors now distinguish selected, unselected and disabled states, with visible borders and selected check marks. Driver label is “Driver/Partner”; “Tourist/User” is retained. Explicit padded touch targets and disabled callbacks match the existing registration busy state. Required-field guidance added. |
| Driver Upgrade / registration application | Existing status, approval and activation explanations retained. Vehicle dropdown can grow for wrapped choices. |
| Create Trip/Hire Post | Pale input and outlined-button borders strengthened through the existing theme. Date/time buttons now occupy separate full-width rows. Required route/schedule guidance added; notes explicitly marked optional. Vehicle dropdown can grow for wrapped choices. Existing counters and saving indicator retained. |
| Bid submission | Vehicle dropdown no longer forces dense/fixed item heights. Existing scrollable form, submit state and validation retained. |
| Support / complaint submission | Category dropdowns can grow for long labels; contact helper text has more lines. Disabled submit explains that contact details are loading. |
| Rating / written review | Existing scrollable form, required-comment error and saving state retained; inherits stronger field borders. |
| Tourist and Driver dashboards | Create, accepted/current trips, completed trips and Account/Support actions reviewed. No screen-specific changes. Stage 14 stream ownership and feed logic retained. |
| Bid list / bid cards / accepted trips | Existing wrapping text, flexible participant headings and actions reviewed; no changes. |
| Lifecycle | State-specific start/end/confirmation actions are in scrollable content. No changes to state handling, deadlines or backend behavior. |
| Chat / manual location sharing | Existing wrapped send/location actions and short-viewport scrolling retained. No changes. |
| Profile Settings | Existing scrolling and flexible name/status content retained. No changes. |
| Registration status / payment / membership | Existing scrolling, wrapping status explanations and activation requirement retained. No changes to payment amounts or eligibility. |
| Admin registration queue / support inbox | Filter chips inherit clearer selected state. Existing wrapped filters, status text, retry and pagination actions retained. |
| Driver administration / support administration | Existing scrollable content, wrapped actions and scrollable dialogs reviewed. No screen-specific changes. |
| Loading / error / empty states | Existing retry/back paths retained. Only the login and support loading labels changed. No error-handling rewrite. |

Shared input hints may wrap to three lines; existing error messages retain their three-line allowance. Registration vehicle and support contact helper text allowances increased from two to four lines. These are readability changes, not new validation rules.

## Files

Created:
- `docs/stage_15_launch_ui_cleanup.md`
- `test/stage_15_launch_ui_test.dart`

Modified:
- `lib/app/app_theme.dart`
- `lib/screens/auth/login_screen.dart`
- `lib/screens/auth/registration_screen.dart`
- `lib/screens/trip/create_trip_post_screen.dart`
- `lib/screens/driver/submit_bid_screen.dart`
- `lib/core/widgets/registration_application_panel.dart`
- `lib/screens/support/support_screens.dart`
- `test/widget_test.dart`

## Test source — not run

Added focused widget cases using the application theme:
- Narrow-screen account selection, displayed labels, selected text contrast, minimum touch target and reachable continue action.
- Disabled selected-chip text contrast.
- Create Trip/Hire controls, long vehicle selection, reachable submit and required-pickup feedback at 360 logical pixels, enlarged text and a simulated keyboard inset.
- Support loading explanation and submit availability after profile loading.

Updated the existing registration wording assertion to expect “Driver/Partner”. No goldens, dependency changes or broad test rewrites.

## Final static review

All changed source and test files were reread. Changes are limited to theme properties, layout, displayed text, dropdown sizing and busy-state presentation. Form submission handlers remain unchanged. Account stored values remain `tourist` / `driver`. No query, stream ownership, Firebase write, business rule, approval, payment, membership, lifecycle or authorization code was changed. No backend, rules, index or dependency files were changed.

The shared theme affects existing consumers, including admin filters; those surfaces must be checked at runtime. Static inspection cannot certify Android contrast, font rendering, keyboard behavior or absence of every overflow. No additional UI launch blocker was established by this source pass; launch readiness remains unverified.

## Deferred non-blocking items

- Broad spacing, typography, branding, animation and dashboard redesign.
- Cosmetic capitalization/punctuation inconsistencies outside changed controls and shortened app-bar titles.
- The existing dashboard notification placeholder requires a later product decision; it is not made into a new notification feature here.
- Profile photos, OTP, phone recovery, email changes, referrals, hotels, maps/travel planner, continuous tracking, calling, phone masking, analytics, notification preferences, account deletion and iOS production work remain out of scope.

## Weekend verification — not performed

CLI/source verification by the developer:
- [ ] `flutter analyze`.
- [ ] Focused Stage 15 widget tests and updated registration tests.
- [ ] Existing registration/upgrade, bidding, support, component, admin and Stage 14 regression tests affected by shared styling.
- [ ] Full `flutter test`.
- [ ] `git diff --check`.
- [ ] Existing launch build and Stage 13/14 verification checklists; this pass does not replace them.

Android screens:
- [ ] Login.
- [ ] Registration role selector, including selected/unselected states and submission busy state.
- [ ] Tourist registration form.
- [ ] Driver registration form.
- [ ] Tourist → Driver Upgrade form.
- [ ] Tourist dashboard.
- [ ] Driver dashboard, including posting and returning to the feed.
- [ ] Create Trip/Hire Post, including date/time pickers and counters.
- [ ] Bid form and bid list.
- [ ] Accepted trip screen.
- [ ] Chat and manual location action.
- [ ] Lifecycle actions for accepted, start requested, in progress, end requested and completed.
- [ ] Rating and written review.
- [ ] Support/Complaint, including loading and long category selections.
- [ ] Profile Settings.
- [ ] Registration/payment/membership status.
- [ ] Admin queue, support inbox and driver administration.

For each applicable screen:
- [ ] Approximately 360 logical-pixel width, portrait orientation.
- [ ] Keyboard open; primary action remains reachable by scrolling.
- [ ] Default and enlarged text; no horizontal overflow or clipped status/helper text.
- [ ] Controls, borders, hints and selected dropdown values readable.
- [ ] Required-field errors visible and actionable.
- [ ] Submit/action buttons reachable; loading and disabled states understandable.
- [ ] Chip selected/unselected/disabled contrast, including admin filter labels.
- [ ] No invisible text or borders.

Stage 15 must remain **IMPLEMENTED — VERIFICATION PENDING** until the developer completes verification.
