# Stage 16 — Production & Release Readiness Review

**Stage 16: IMPLEMENTED — VERIFICATION PENDING**

**Not production ready.** Source preparation is complete for this pass; signing, backend deployment confirmation, policy preparation, release packaging and Android verification remain outstanding.

Developer-supplied baseline: branch `ceylon-travel-mvp`, commit `ded163b Improve launch-critical UI visibility`, CI GREEN. Stage 13 runtime/deployment verification and Stage 14/15 verification remain pending. Git and deployed state were not inspected.

## Scope and execution boundary

Only filesystem reads, source-text searches and file edits were performed using the explicitly authorized Node-backed filesystem tool. No project JavaScript/TypeScript was executed. No shell/CMD/PowerShell, Node commands, npm, Flutter/Dart, Git, tests, builds, Firebase CLI, gcloud, deployments, keystore/signing commands, subprocesses, emulator, device, browser or dependency operations were run. Local installed Flutter/plugin source was read only. Current online Play policies were not checked; policy declarations require operator review before submission.

## Android identity, branding and version

- `android/app/build.gradle.kts`: namespace and applicationId are both **lk.ceylontravel.app**.
- MainActivity is at `android/app/src/main/kotlin/lk/ceylontravel/app/MainActivity.kt`, with the matching package. Main manifest uses `.MainActivity`; debug/profile manifests do not override identity.
- `android/app/google-services.json` exists and its Android client package matches. Its mobile app identifier matches generated `lib/firebase_options.dart` and `firebase.json`. Project references consistently identify **ceylon-travel-mvp**; no new Firebase app/configuration was created.
- Fixed main-manifest launcher label from `taxi_app` to **Ceylon Travel**. Flutter MaterialApp already uses the correct title and disables the debug banner. Internal Dart package name `taxi_app` and its template description were left alone; they are not the Android launcher label.
- `pubspec.yaml` already has **1.0.0+1**. Retained: Android versionName **1.0.0**, versionCode **1**. Gradle obtains both from Flutter. CLI build overrides remain possible, so verify the packaged values. Before each new Play upload use an unused, increasing versionCode/build number; if 1 was previously uploaded, choose the next appropriate number. Do not repeatedly bump without an upload plan.
- No package mismatch was found in inspected Android/Firebase source. Release artifact identity remains unverified.

## Release signing — source fixed, credentials still required

Release previously selected `signingConfigs.getByName("debug")`. It now selects a separate release configuration loaded from local **android/key.properties**. No debug fallback remains.

The new `verifyReleaseSigning` Gradle task is a prerequisite of `preReleaseBuild` and `validateSigningRelease`. It rejects missing properties, blank required fields and an unavailable keystore path without printing credentials. Gradle still must validate the actual keystore, alias and passwords during packaging. Missing local signing files do not select debug credentials and are not required by ordinary debug tasks. These Gradle behaviors have been reviewed in source, not executed.

Created `android/key.properties.example` with blank values only. `storeFile` resolves relative to the Android project directory, or may be absolute. Windows paths should use forward slashes; Java properties escaping applies to passwords/backslashes. Existing `android/.gitignore` already ignores key.properties and keystores. Root ignore rules now protect key.properties, *.jks, *.keystore, local .env files and common service-account key filenames throughout the repository. Ignore rules do not remove files that were already tracked.

### Stage 17 signing actions — developer only

1. Decide the Play App Signing/upload-key arrangement and ownership. Obtain or create the protected upload keystore through the approved local signing procedure; do not reuse Android's debug key. No keystore was generated in Stage 16.
2. Store it outside the repository where practical, restrict access, and securely back up the keystore, alias and passwords. Do not paste them into source, chat, logs or build artifacts.
3. Copy the blank example locally to `android/key.properties`; populate storeFile, storePassword, keyAlias and keyPassword with the real protected values. The example itself must remain blank.
4. Check ignore and tracked-file state before any commit. A previously tracked credential requires removal from tracking and exposure review; merely adding an ignore pattern is insufficient. Do not upload signing files as CI artifacts.
5. Verify a release build without credentials fails with no debug fallback, then configure credentials and build the candidate. Verify a debug build remains usable independently. If adding Android release CI later, inject these files securely and remove them after use; current CI does not package Android.
6. Inspect the resulting signature, package/version and certificate identity. Register upload/app-signing certificate fingerprints in Firebase only as required by the configured Auth/API integrations; Play-distributed APKs use the Play app-signing certificate. Verify Auth from the actual distributed build.

## Manifest, permissions and release compatibility

| Item | Source assessment / required verification |
| --- | --- |
| INTERNET | Added explicitly to main manifest for release networking. Debug/profile already declared it, and the cached FCM plugin also declares it. This removes reliance on plugin merging; an actually missing merged permission was not proven. |
| POST_NOTIFICATIONS | Already declared. FcmService requests permission after authentication, remembers the prompt attempt, checks authorization before saving tokens, and disables auto-init when denied. Check first prompt, denial, later enablement and Android 13+ behavior. |
| ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION | Already declared for the user-initiated one-shot chat location share. Service uses getCurrentPosition with timeout, not a position stream. No background-location permission or continuous tracking added. Check approximate/precise, denied, permanently denied and device location disabled. |
| Camera / evidence | Android selfie uses image_picker camera intent; documents/slips allow capture or gallery. Cached image_picker documentation says no Android configuration is required and its manifest does not declare CAMERA. No speculative CAMERA, storage or broad media permission added. Test camera availability, cancellation, gallery/system picker and return to the app. |
| Plugin permissions/components | Cached Messaging adds INTERNET, WAKE_LOCK, ACCESS_NETWORK_STATE and notification permission; local notifications adds VIBRATE and notification permission. Image picker supplies a non-exported FileProvider. Geolocator declares its service, but app source does not start continuous/background tracking. Inspect the final merged manifest including transitive native dependencies. |
| Activity | Exported launcher activity, singleTop, Flutter embedding metadata, themes and adjustResize are present. No cleartext/network-security development override found. |
| SDK / toolchain | Java/Kotlin target 17, AGP 8.11.1, Kotlin 2.2.20, Gradle wrapper 8.14, core-library desugaring 2.1.4 retained. Flutter provides compile/target/NDK defaults; minimum is at least 24. Installed Flutter 3.41.7 source has compile/target 36 and min 24; CI pins that Flutter version. Confirm actual release toolchain and manifest values, current Play target requirements and native-library/page-size compatibility at submission. No dependency upgrade performed. |
| R8 / resources | No new shrinking/obfuscation enabled. Flutter's existing Gradle plugin configures release shrinking; installed local-notifications v19.5 documentation states Gson ProGuard rules are provided automatically. Notification icon is explicitly referenced in the main manifest as well as by its runtime name. Verify release notification display/taps and resource retention in the AAB; no speculative keep rules added. |

Camera process death remains a verification risk: the app does not call image_picker.retrieveLostData. If Android kills the app during capture, the pending photo can be lost and require a retake; unsaved form input can also be lost. Test recovery on a low-memory device before approving registration readiness. No evidence-recovery feature was added.

## Firebase / network production references

- main.dart awaits Firebase initialization using DefaultFirebaseOptions before runApp. Android configuration is present; initialization/background FCM use the same generated options.
- Auth, Firestore, Storage and Messaging use the default Firebase app. Driver/application commands are Firestore operation documents consumed by trusted Functions; there is no new client callable endpoint or duplicate workflow.
- Source search found no localhost, 127.0.0.1, 10.0.2.2, client emulator activation or local development endpoint in lib/ or deployed functions/src paths. Local emulator support remains confined to test/operator documentation and test configuration.
- The ignored local Functions environment file exists with region, service-account and HTTPS worker-URI parameters. Values were not copied here. It contains configuration references, not an embedded HMAC/private key. Source presence does not establish deployed URIs, IAM or environment correctness.
- DRIVER_IDENTITY_HMAC_KEY is a Secret Manager parameter attached to both operation workers. Preserve its existing value/fingerprint and identity registries; do not rotate it casually or reset counters.
- Verify Email/Password Auth enabled, Firebase API restrictions/certificates, Firestore database/rules/indexes, Storage bucket/rules/cross-service rule access, FCM delivery, billing/quotas, service accounts, task invoker/enqueuer permissions and worker URIs. No live resource state was checked.
- firebase.json points to Functions source `functions`, codebase **trip-lifecycle**, runtime **nodejs22**; package entry is `lib/src/index.js` and predeploy compiles TypeScript. Existing generated output is not evidence that latest source is deployed. Use the reviewed build before deployment.

## Exact backend deployment inventory

Deployment state for every row is **UNKNOWN**. Earlier Stage 13 documentation explicitly records pending deployment; Stage 14 also requires rules deployment, but later deployment confirmation is absent. No resource can be marked ALREADY DEPLOYED from this review. For changed resources below, **deployment is needed if the operator cannot establish that the reviewed revision is already live**. Stage 16 changes no Function, rule or index source.

| Resource / exact name | Evidence / action after successful verification |
| --- | --- |
| Function **processRegistrationApplication** | Exported from driver_administration_trigger.ts through index.ts. Stage 13B/C-1 changed same-UID upgrade operations/approval. Verify/deploy this existing trigger on users/{uid}/application_operations/{operationId}. Requires existing HMAC secret and DRIVER_ADMIN_* settings. |
| Function **notifyRegistrationReviewEvent** | Existing index.ts trigger on registration_applications/{uid}/history/{operationId}, using workflow_push.ts. Stage 13C-2 added driver_upgrade_* notification handling. Verify/deploy this existing export; no new trigger. |
| Firestore rules **firestore.rules** | firebase.json configured rules file. Stage 13 safe-profile/upgrade authorization plus Stage 14 operational-driver and reassigned-chat protections must be live. Deploy reviewed current rules if behind. |
| Firestore composite **users**, COLLECTION scope | Stage 13C-2 fields: driverUpgradeStatus ASC, accountType ASC, __name__ ASC in firestore.indexes.json. Confirm deployed and READY; exercise actual queue queries. Preserve other declared indexes. |
| Storage rules **storage.rules** | Stage 13B changed registration_evidence upload eligibility for editable Tourist upgrades. Stage 14/16 did not change this file. Verify/deploy only if that prior change is still outstanding; do not assume Storage can be omitted solely because Stage 16 did not edit it. |

Existing launch dependencies exported by the same codebase, also **UNKNOWN** deployment status; no Stage 16 changes and no evidence here that they all require redeployment:

- **processDriverAdministration** — identity/payment/membership operations, existing HMAC secret and DRIVER_ADMIN_* configuration.
- **autoStartTrip**, **autoCompleteTrip**, **scheduleTripLifecycle** — private task workers and scheduling. Confirm actual HTTPS worker URIs, region, queues, invoker/enqueuer IAM and LIFECYCLE_* configuration; never make workers public as a workaround.
- **publishUserProfile**, **publishUserReputation**, **publishWrittenReview** — privacy-safe public projections.
- **notifyTripChatMessage**, **notifyTripBidCreated**, **notifyTripTransition** — trip/chat notifications.
- **syncNotificationStaffTokens**, **notifySupportRequestCreated**, **notifySupportReplyCreated**, **notifyDriverOperationCompleted**, **notifyFoundingOfferClosed** — staff discovery and existing workflow notifications.

There are 17 exported Functions in the inspected entry points. requeue_pending.ts, seed_public_profiles.ts and set_admin_claims.ts are trusted operator tools, not additional deployed exports. Do not run them as routine deployment steps or reset/backfill data speculatively. Coordinate backend/rules/client rollout: current new submissions require Agreement 1.1; preserve historical accepted versions.

## Logging, secrets and production debug settings

- No print()/debugPrint() calls found in lib/. No client logging of passwords, identity, evidence paths, FCM/auth tokens or payment details was found in inspected source.
- Existing Functions log lifecycle trip IDs, phase/outcome/deadlines and operational errors; push logs use generic failure messages. No explicit sensitive payload logging found. Trusted admin-claim operator tool logs target UID for its audit result. Useful operational logging was retained; this is not proof that every vendor exception is free of identifiers. Apply production log access/retention controls.
- No private-key header, service-account private-key JSON structure, common secret-token pattern, keystore or key.properties file was found in inspected repository files. No actual credential was added or removed. Firebase client configuration is present and is not treated as a server secret.
- Pattern scanning is not a historical secret audit. Git history/index and remote access were deliberately not inspected. Before release, check tracked credentials/history; if exposure is found, remove it safely and arrange appropriate rotation/revocation. Do not automatically rotate the identity HMAC key without registry migration planning.
- Existing functions/.gitignore already ignores local environment files/generated output. Root ignores now provide additional credential protection. Common filename patterns are safeguards, not a guarantee for arbitrary filenames.
- Removed the production Welcome screen's **View Demo Flow** button, its navigation callback and import. It exposed an **Admin Demo** account chooser. The legacy chooser file remains unreferenced by production entry routes; legitimate claim-gated Account & Support admin tools remain.
- MaterialApp debug banner was already false. No fake-login, hardcoded-user or disabled-verification switch was identified in reviewed production entry paths.

## Account / data safety review

AuthService delegates passwords to Firebase Auth; no password persistence was found. AuthPreferencesService retains only the last successful email. Profile phone changes reauthenticate and refresh trusted auth_time; allowed profile writes remain narrow. Profile session invalidation and FCM token/intent ownership checks protect account switching. Logout clears navigation and detaches notifications through the existing path.

Primary-admin access uses Auth claims, not users document roles. Trusted operation workers check live admin and disabled state. Support-only privileges remain separate. Account routing/driver eligibility retains trusted approval, identity, payment, membership/expiry and active-state requirements; accountType alone does not activate a driver. Existing Firestore/Storage rules remain authoritative, but must actually be deployed. Disabled Auth session/token-refresh behavior and device cache/account-switch privacy still require runtime verification; immediate remote revocation is not certified here.

Evidence uses authenticated Storage bytes, owner/primary-admin access, random revision-scoped paths and no public download URL in the reviewed service. Image preparation removes metadata from uploaded copies. Captured originals may exist temporarily in plugin/device cache; uploaded evidence and immutable application/history records have no user deletion or automated retention policy implemented here. Do not promise immediate deletion, zero local retention or end-to-end encryption.

## Privacy, agreement and support release gates

A publicly accessible **Privacy Policy URL** is required by the requested launch plan because the app handles account/contact data, identity documents, manual location, Firebase processing and user-generated content. No public privacy-policy URL/link or public support email was found in reviewed app source. Do not invent either. Provide the real policy and accessible in-app/Play listing entry points before submission.

Registration guidelines / agreement **1.1** already exist, including acceptance records. They identify **VerTech Solutions as the planned operator name, not yet formally registered**, and explicitly avoid claiming a lawyer-reviewed final contract. This wording and historic acceptance records were not changed. The operator must review privacy/terms content, retention, identity verification practices, lawful disclosures and support details; no full legal contract was drafted.

Existing authenticated Account & Support, Contact Us / Support and complaint flows remain. They do not substitute for a public privacy URL or a contact path for people who cannot sign in. Supply a real monitored contact email and public help path.

**Account deletion remains unimplemented, but its Play/privacy compliance impact is unresolved—not certified as a post-launch non-blocker.** Before submission, confirm current account/data-deletion obligations for an app offering account creation, including any required in-app request path and external web resource. Resolve applicable requirements and retention exceptions before release. This stage adds no deletion functionality and makes no policy-compliance claim.

## Preliminary Data Safety inventory — not final declarations

| Source-derived data | Purpose / observed handling to validate |
| --- | --- |
| Full name, email, phone, city/district | Auth/profile, contact, registration and support. Last successful email is also retained locally. |
| Firebase UID / account identifiers | Auth, ownership, workflow/audit relationships and access control. |
| NIC / Driving Licence numbers and keyed registry identifiers | Manual identity review and uniqueness; private workflow records and trusted keyed HMAC registries. |
| Document images / selfie | Registration/upgrade identity evidence in private Storage; selfie is manual-review evidence, not a demonstrated biometric-authentication system. |
| Pickup/drop, schedule, passenger/baggage counts, notes, creator/assignment identifiers | Trip/Hire coordination and lifecycle/history. Open-feed visibility must be reflected in disclosures. |
| Manually shared coordinates | Current-trip chat location messages; external Maps receives selected coordinates when opened. No continuous tracking in reviewed code. |
| Chat content | Creator/current assignment communication and permitted history. |
| Bid price, vehicle type/details/registration, duration and message | Private offers, acceptance and performing-driver information. |
| Ratings / written reviews / reputation | Trip feedback and privacy-safe public projections. Public content and participant identity display require disclosure review. |
| Support/complaint messages, phone, references and staff replies | Customer assistance and administrative processing. |
| Payment proof / deposit details / amounts / references / status, membership entitlement | Manual registration payment review and activation. Banking details visible on evidence must be considered. No new payment processor introduced. |
| FCM device token, installation identifier, permission state and timestamps | Push delivery, token maintenance and account binding. Generic notification payloads do not eliminate device-identifier processing. |
| Revision, agreement, admin action, lifecycle and delivery audit metadata | Security, operations, deduplication and historical accountability. |

Final Play Data Safety answers must match actual production collection, purposes, required/optional behavior, public/participant/admin visibility, sharing, retention/deletion, transport/storage protection and Firebase/Google/vendor processing. Inspect vendor behavior and operational logging too. Do not infer questionnaire answers such as “not shared”, “not collected”, “optional”, or deletion guarantees from this preliminary inventory.

## Release assets

- Five Android ic_launcher PNGs exist (48/72/96/144/192 pixels). Byte comparison with the installed Flutter template found all five unchanged **stock Flutter icons**. A product-approved production launcher/store icon is still required as a release preparation decision; no graphics were created.
- No Android adaptive-icon XML/foreground/background resources were found. Prepare approved adaptive assets later if required for the intended launcher presentation.
- Native splash drawable is the template white background with no active logo layer. Flutter splash/brand text exists. Branding review is pending; generic splash is not itself a demonstrated startup failure.
- Notification drawable ic_stat_trip_chat.xml exists and is referenced in the manifest. Verify it in release notifications.
- No Android store feature graphic or phone screenshot set was found in the repository. Web/iOS icons are not treated as an approved Android store asset package.

## Google Play preparation checklist — operator completes

- [ ] Google Play Developer account and required verification/access.
- [ ] Create app; confirm package **lk.ceylontravel.app** and name **Ceylon Travel**.
- [ ] Protected upload key / Play App Signing arrangement and signed production AAB.
- [ ] Confirm versionName/versionCode and upload history.
- [ ] Short description and full description that match actual MVP behavior.
- [ ] Approved app/store icon, feature graphic and phone screenshots from the release build.
- [ ] Public Privacy Policy URL, in-app policy access and monitored contact email.
- [ ] Resolve applicable account/data-deletion request requirements and public resource.
- [ ] App category and target audience.
- [ ] Content rating questionnaire; do not fabricate answers.
- [ ] Data safety form based on verified production behavior/retention/vendors.
- [ ] Ads declaration based on actual behavior.
- [ ] App access/login instructions and separately managed reviewer credentials if required. Include how review can reach approved/activated roles; never put test credentials in source or bypass verification.
- [ ] Testing/release track and any account-specific production-access testing requirements.
- [ ] Countries/regions and release notes.
- [ ] Current target SDK, native library compatibility, signing and other Play technical/policy requirements confirmed at submission.

## Outstanding blockers / manual decisions

1. **Signing credentials and Android package verification:** fail-closed configuration is prepared, but no key/properties or signed release artifact exists from this task.
2. **Unknown backend readiness:** confirm/deploy the exact Stage 13/14 resources above after tests, plus existing task/secret/IAM prerequisites. Green CI does not prove deployed security rules or Functions.
3. **Privacy/support/policy readiness:** real privacy URL and accessible content, contact email, reviewed terms/disclosures, retention decisions and account-deletion compliance resolution remain.
4. **Production assets/store setup:** stock launcher icons and missing store graphics/screenshots require the operator's approved assets; no asset redesign was attempted.
5. **Android verification:** current .github/workflows/flutter-ci.yml analyzes/tests Flutter and builds web only. It does not verify Android Gradle, signing, AAB, merged manifests, native plugins or release permissions. Stage 13/14/15 runtime checks remain outstanding.
6. **Camera process-death recovery and remote account revocation:** verify real behavior before launch; source review alone cannot establish acceptable recovery/privacy behavior.

No new app feature, pricing rule, counter change, membership rule, privilege expansion, notification system, dependency upgrade, iOS production change or Firebase resource was introduced.

## Files and test source

Created:

- android/key.properties.example — blank template, no credentials.
- docs/stage_16_production_release_readiness.md — this report/checklist.

Modified:

- android/app/build.gradle.kts — protected local release signing with no debug fallback.
- android/app/src/main/AndroidManifest.xml — Ceylon Travel label and explicit INTERNET.
- .gitignore — repository-wide signing/local environment/common credential-file protection.
- lib/screens/welcome_screen.dart — remove public demo navigation.
- test/widget_test.dart — Welcome assertions require demo/admin-demo labels absent while Login/Register remain.

No tests were added merely for configuration/documentation. The existing widget assertion update covers the only changed application behavior. No test was run.

## Deferred release verification — nothing below was run

CLI/source checks, using the existing toolchain and dependencies:

- [ ] flutter analyze.
- [ ] flutter test test/widget_test.dart, then full flutter test (including Stages 13–15).
- [ ] npm --prefix functions run build and npm --prefix functions test for outstanding Stage 13 backend verification; Stage 16 did not change backend code.
- [ ] npm --prefix rules-tests test with the documented local demo-project Firestore emulator setup.
- [ ] npm --prefix rules-tests run test:upgrade-storage with the documented demo-project Firestore/Storage emulator setup, because Stage 13 Storage deployment remains unconfirmed. Never run destructive emulator suites against production.
- [ ] git diff --check; review all changes and actual tracked credential/ignore state.
- [ ] Verify deployment inventory against actual live revisions; deploy only reviewed outstanding resources after successful tests; wait for indexes READY.
- [ ] Complete protected signing setup; check missing/incomplete signing fails and debug builds remain independent.
- [ ] flutter build appbundle --release.
- [ ] Inspect AAB application ID, version, release/non-debuggable flag, signing certificate, merged permissions, manifest components, launcher/notification assets, native ABIs/page-size compatibility and Firebase resources.
- [ ] Install/test the release artifact through an appropriate Android testing method, preferably the intended Play testing track. A debug run is insufficient.

Release runtime checks:

- [ ] Firebase Auth registration/login, restart/session restoration, logout/login, disabled account and account switching.
- [ ] Firestore feeds/transactions/rules, Storage evidence access and upload, Messaging and all required Functions.
- [ ] Notifications allowed/denied/re-enabled; foreground/background/terminated delivery, icon and authenticated tap routing.
- [ ] Manual location permission, approximate/precise result, denied/blocked states, timeout and external Maps.
- [ ] Camera/selfie and document/slip selection, cancellation, upload/preview, process death, low-memory restart and no unrelated-account evidence access.
- [ ] New Tourist and Driver applications; primary-admin review, correction/rejection/approval; support-only/revoked-admin denial.
- [ ] Tourist-to-Driver upgrade on the same UID; approved driver remains non-operational until payment/membership activation.
- [ ] Existing quote/payment/membership/founding entitlement rules and registration numbering; no counter reset or fee change.
- [ ] Full Trip/Hire journey: post/feed/bid/accept/chat/manual location/start/end/automatic deadlines/completion/rating/review; creator cancellation and driver cancellation/reopen/reassignment privacy.
- [ ] 360-ish portrait layouts, keyboard/actions and readable controls/statuses from Stage 15.
- [ ] Public privacy/support access and reviewer instructions; final Play declarations match verified behavior.

Final static review: all Stage 16 edits were reread. No secret or test credential was added; no commit was made; submission/business logic, Firebase rules/exports, account privileges, commercial rules and dependencies remain unchanged. Keep **IMPLEMENTED — VERIFICATION PENDING** until the developer completes the required verification and resolves release gates.
