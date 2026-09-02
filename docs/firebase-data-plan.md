# Firebase Backend Architecture - Ceylon Travel

## Purpose

This document is the authoritative Firebase backend specification for the Ceylon Travel project.

It replaces the earlier MVP-only data plan with the finalized backend architecture for authentication, Firestore data, Cloud Storage media, security rules, notifications, backup planning, and implementation order.

Current status:

- Implemented now: Flutter UI/MVP foundation and Firebase core configuration in the Flutter project.
- Planned next: real Firebase backend implementation, beginning with Firebase Authentication, Firestore/Storage provisioning, and security rules.
- Deferred: driver verification workflow, admin verification dashboard, production backup automation, advanced moderation, automated server-side timeout processing if it requires additional backend services, Google Maps integration, advanced analytics, and production deployment/hardening.

Firebase is the source of truth. Flutter UI must never be treated as the security boundary. Security-sensitive operations must be enforced by Firebase Security Rules and, where necessary, trusted server-side/backend mechanisms.

## Firebase Services

Use these Firebase services:

- Firebase Authentication
- Cloud Firestore
- Cloud Storage for Firebase
- Firebase Cloud Messaging (FCM)
- Firebase Hosting later, only if web deployment is required

Do not introduce Cloud Functions or Firebase App Hosting unless a later feature genuinely requires them.

## Authentication

Use Firebase Email/Password authentication.

Email is required because the authentication mechanism is Email/Password. Phone number is profile information only in Year 1. Do not use SMS or phone authentication in Year 1.

Registration fields:

- Full name
- Email
- Password
- Confirm password
- Phone number
- City/District
- Account type: Tourist/User or Driver

Account type values:

- `tourist`
- `driver`

Rules:

- Never store plaintext passwords in Firestore.
- Admin must not be selectable during public registration.
- Admin privileges must be controlled separately from the normal Tourist/Driver account type.
- Public registration must not be able to create admin accounts or assign privileged roles.

## Users

Use one main users collection:

```text
users/{uid}
```

Fields:

```text
uid
fullName
email
phoneNumber
city
accountType
profilePhotoPath
status
averageRating
completedTripsCount
cancelledTripsCount
cancellationRate
createdAt
updatedAt
```

Suggested `status` values:

```text
active
warning
blocked
```

Driver-specific information must be stored inside the user document rather than in a duplicate identity collection:

```text
driver:
  vehicleType
  vehicleNumber
  operatingArea
  availableAreas

verification:
  status
  submittedAt
  reviewedAt
  reviewedBy
  rejectionReason
```

Verification status values:

```text
pending
approved
rejected
```

Driver verification is a mandatory final-product feature, but implementation is deferred until the driver-verification phase.

Security requirements:

- Client must never be allowed to set verification approval.
- Client must not be allowed to arbitrarily modify rating or cancellation statistics.
- Server/trusted backend logic must control security-sensitive derived fields.
- Users may update only fields they are authorized to update.
- Admin privileges must be managed separately from `accountType`.

## Driver Media And Documents

Cloud Storage is used for files. Do not store image or document bytes in Firestore.

Store Storage paths and required metadata in Firestore. Prefer Storage paths over public download URLs.

Storage paths:

```text
profiles/{uid}/profile.jpg

vehicles/{uid}/vehicle-01.jpg
vehicles/{uid}/vehicle-02.jpg
vehicles/{uid}/vehicle-03.jpg

driver-private/{uid}/driving-license.jpg
driver-private/{uid}/vehicle-registration.jpg
driver-private/{uid}/other/{fileName}
```

Access rules:

- Verification documents are private.
- Only the driver and an authorized verification/admin process may access private verification documents.
- Other tourists/drivers must not have access to private verification documents.
- Profile and vehicle photos may be accessible to authenticated users where required by the product UI.
- Storage security rules must still control all access.
- Do not expose private driver documents through public download URLs.

## Mandatory Image Processing

Every image upload must follow this flow:

1. Select file.
2. Validate file type.
3. Resize on device.
4. Compress on device.
5. Verify final size.
6. Upload to Cloud Storage.
7. Save Storage path/metadata in Firestore.

Do not upload the original high-resolution image unless explicitly required later.

Initial target limits:

- Profile image: approximately 1 MB
- Vehicle image: approximately 23 MB
- Verification documents: approximately 23 MB each

Exact limits can be finalized during implementation.

## Trip Posts

Use:

```text
trip_posts/{tripId}
```

Fields:

```text
id
creatorId
creatorType
postType
touristId
driverId
pickupLocationText
dropLocationText
tripDate
tripTime
adultsCount
kidsCount
baggageCount
vehiclePreference
notes
status
acceptedBidId
acceptedDriverId
createdAt
updatedAt
```

`creatorType` values:

```text
tourist
driver
admin
```

`postType` values:

```text
tourist_request
driver_reassignment
```

Driver-created posts are specifically for reassigning an already hired trip to another driver. Preserve the original tourist/customer relationship when a driver creates a reassignment post.

Status values:

```text
open
bidAccepted
pendingTrip
started
completed
cancelled
expired
```

Review status names during implementation and keep them consistent throughout the app.

Security requirements:

- Authenticated users can create trip posts.
- Only authorized users can modify their own posts.
- Driver reassignment posts must preserve the original tourist/customer relationship.
- Only the post creator can accept a bid.
- Security must not depend on hiding UI buttons.

## Private Bids

Do not use a global bids collection.

Use:

```text
trip_posts/{tripId}/bids/{bidId}
```

Fields:

```text
id
driverId
driverName
driverRating
completedTrips
cancellationRate
vehicleType
price
estimatedTravelTime
message
status
createdAt
updatedAt
```

Bid status values:

```text
submitted
accepted
closed
cancelled
```

Security requirements:

- Post creator can read bids for their post.
- Driver can read their own bid.
- Other drivers cannot read another driver's private bid.
- A driver who created a reassignment post follows the appropriate owner rules for that post.
- Only eligible drivers can submit bids.
- Accepting a bid must be atomic so that two drivers cannot simultaneously become the accepted driver.

## Trips

Use:

```text
trips/{tripId}
```

Fields:

```text
id
tripPostId
creatorId
creatorType
touristId
driverId
acceptedBidId
acceptedBidPrice
status
startRequestedAt
startConfirmedAt
endRequestedAt
endConfirmedAt
cancelledBy
cancelReason
createdAt
completedAt
```

Trip status values:

```text
pending
startRequested
started
endRequested
completed
cancelled
```

Business rules:

- A trip is created after the post creator accepts one bid.
- Driver requests start.
- Tourist/post creator confirms start.
- Driver requests end.
- Tourist/post creator confirms end.
- Both sides may cancel according to cancellation rules.
- Only authorized participants may change trip state.
- Cancellations must update account statistics only through trusted logic.

The existing 3-minute confirmation and 15-minute automatic confirmation/completion behavior is a business requirement, but automatic server-side enforcement must be designed later. Do not rely on a client-only timer for security-sensitive state changes.

## Chat

Chat belongs to the trip.

Use:

```text
trips/{tripId}/messages/{messageId}
```

Fields:

```text
senderId
senderName
messageType
text
locationLat
locationLng
locationMapUrl
imagePath
createdAt
```

Message type values:

```text
text
location
image
system
```

Access rules:

- Only the tourist/post creator and accepted driver may access the trip chat.
- Only authorized participants can read/write trip messages.
- Location sharing is available only inside the accepted trip chat.

Chat lifecycle:

- During active trip: normal two-way chat.
- After trip is completed: chat remains available for 24 hours for both participants.
- During that 24-hour period: both participants can continue sending messages.
- After 24 hours: the entire chat remains visible/readable, but no new messages may be sent.
- Firebase Security Rules/backend logic must enforce the cutoff using trusted timestamps.
- Do not rely only on Flutter UI to enforce the 24-hour rule.

Chat images must be stored in Cloud Storage:

```text
chat-media/{tripId}/{messageId}.jpg
```

Firestore stores only the Storage path/metadata.

## Ratings

Use:

```text
ratings/{ratingId}
```

Fields:

```text
id
tripId
fromUserId
toUserId
ratingValue
comment
createdAt
```

Rules:

- Rating only after trip completion.
- Only trip participants may rate each other.
- Prevent duplicate ratings for the same participant/trip.
- Rating statistics must not be freely client-writable.
- Aggregate rating fields on `users/{uid}` must be updated only through trusted logic.

## Complaints

Use:

```text
complaints/{complaintId}
```

Fields:

```text
id
tripId
reportedById
reportedAgainstId
reason
details
status
createdAt
resolvedAt
resolvedBy
```

Status values:

```text
open
reviewing
resolved
rejected
```

Rules:

- Users may create complaints according to authorization rules.
- Complaints must not be publicly readable.
- Complaint resolution is an admin/moderation concern.

## Notifications

Use:

```text
notifications/{notificationId}
```

Fields:

```text
recipientId
type
title
body
relatedTripId
relatedTripPostId
read
createdAt
readAt
```

Notifications should support:

- New bid
- Bid accepted
- Bid closed
- New chat message
- Trip start request
- Trip start confirmation
- Trip end request
- Trip completion
- Cancellation
- Rating reminder
- Verification status changes

FCM is part of the current backend architecture. Notification document creation, FCM token usage, and push delivery must be protected so users cannot send arbitrary trusted notifications as another user.

## FCM Device Tokens

Store device information under the user:

```text
users/{uid}/devices/{deviceId}
```

Fields:

```text
fcmToken
platform
createdAt
updatedAt
lastSeenAt
```

Rules:

- Tokens must be protected so one user cannot access another user's device tokens.
- Users may manage only their own device token documents.
- Token writes must be scoped to the authenticated user.

## Firestore Security Model

Firestore Security Rules must enforce:

- Authentication required for protected operations.
- Users can read/write only their own private profile fields.
- Public registration cannot create admin accounts.
- Admin privileges must be separately controlled.
- Users can create trip posts.
- Only authorized users can modify their own posts.
- Only eligible drivers can submit bids.
- Bid privacy must be enforced.
- Only the post creator can accept a bid.
- Accepted trip participants can access trip chat.
- Only authorized participants can read/write trip messages.
- Chat becomes read-only after the 24-hour post-completion window.
- Only trip participants can create/read relevant ratings.
- Complaints are private.
- Driver verification documents are private.
- Security must never depend only on hiding UI buttons.

Security-sensitive derived fields must not be freely client-writable, including:

- `users.averageRating`
- `users.completedTripsCount`
- `users.cancelledTripsCount`
- `users.cancellationRate`
- `users.verification.status`
- `trip_posts.acceptedBidId`
- `trip_posts.acceptedDriverId`
- Trip status transitions requiring participant authorization

Where Firestore Security Rules are not sufficient for atomic or scheduled business logic, use a trusted backend mechanism later. Do not add Cloud Functions only by default; add them only when a real feature requires trusted server-side execution.

## Storage Security Model

Cloud Storage Security Rules must enforce:

- Authentication required for protected files.
- Users can upload/update only their own profile media.
- Vehicle photos are writable only by the owning driver.
- Verification documents under `driver-private/{uid}` are private to the driver and authorized verification/admin process.
- Other tourists/drivers cannot read private driver verification documents.
- Chat media is readable only by authorized trip chat participants.
- Chat media uploads must be limited to authorized chat participants and valid trip/message context.
- File type and size restrictions must be enforced where possible in Storage Rules and app validation.

## Firestore Query Efficiency

Design queries to:

- Use indexed fields.
- Use pagination/limits.
- Avoid unnecessary realtime listeners.
- Avoid repeatedly downloading large collections.
- Read only data required by the screen.

Do not create unnecessary composite indexes in advance. Add indexes when actual queries require them.

Likely indexed query patterns will come from:

- Open trip post lists by `status`, `postType`, trip date, and location/area fields.
- User-owned trip posts by `creatorId`.
- Driver-owned bids through scoped subcollection reads.
- User trip history by participant ids and status.
- Notifications by `recipientId`, `read`, and `createdAt`.

Finalize composite indexes during implementation based on the actual Firestore queries used by the app.

## Backup And Disaster Recovery

Development:

- No expensive automated backup configuration yet.
- Use source control and controlled Firebase test data.

Before production:

- Configure Firestore backup strategy.
- Daily backup.
- Weekly backup/longer retention where appropriate.
- Test restoration before launch.
- Include authentication/account recovery strategy.
- Create a separate Storage backup/retention policy because Firestore backups do not automatically back up Storage files.

Do not enable every backup feature automatically. Review cost before production.

## Cost Control

Keep Year 1 infrastructure as low-cost as possible.

Rules:

- No SMS authentication in Year 1.
- Avoid Google Maps until genuinely needed.
- Avoid Cloud Functions until genuinely needed.
- Compress images before upload.
- Avoid storing files in Firestore.
- Use pagination.
- Limit realtime listeners.
- Avoid unnecessary reads.
- Avoid unnecessary Storage duplicates.
- Configure Google Cloud/Firebase budget alerts before production.

Budget alerts are alerts, not guaranteed spending caps.

## Firebase Region

Do not hard-code a Firebase/Firestore/Storage region in this document yet.

The region must be deliberately selected before production provisioning because it affects latency, pricing, and data-residency considerations.

## Data Privacy

Privacy rules:

- Minimize stored personal data.
- Do not duplicate identity information unnecessarily.
- Do not store passwords.
- Keep driver verification documents private.
- Store Storage paths rather than public file URLs where possible.
- Do not expose private driver documents through public download URLs.
- Avoid storing sensitive identity data unless required for verification.
- Keep complaint and moderation data private.

## Implementation Status

Implemented now:

- Flutter UI/MVP foundation.
- Firebase core configured in the Flutter project.

Planned next:

- Real backend implementation.
- Firebase Authentication with Email/Password.
- Firestore and Storage provisioning.
- Firestore and Storage security rules.
- User profile creation backed by Firestore.

Deferred/future:

- Full driver verification workflow.
- Admin verification dashboard.
- Production backup automation.
- Advanced moderation.
- Automated server-side timeout processing if it requires additional backend services.
- Google Maps integration.
- Advanced analytics.
- Production deployment/hardening.

Do not rewrite existing UI unnecessarily while implementing the backend.

## Backend Implementation Order

Implement in this order:

1. Firebase project configuration
2. Firestore database
3. Storage bucket
4. Authentication
5. Firestore security rules
6. Storage security rules
7. User profile creation
8. Trip posts
9. Private bids
10. Bid acceptance
11. Trips/status state machine
12. Chat/messages
13. 24-hour post-completion chat rule
14. Notifications + FCM
15. Ratings
16. Complaints
17. Driver media
18. Driver verification
19. Backup/restore preparation
20. Production hardening

## Explicit Non-Goals For This Document

This document does not:

- Create Firebase resources.
- Implement backend code.
- Modify Flutter/Dart source files.
- Modify `pubspec.yaml`.
- Select a production Firebase region.
- Introduce Cloud Functions/App Hosting by default.
- Define final UI copy or screen layouts.

## Next Step

After this document is finalized, the project moves into real Firebase backend implementation, beginning with Firebase Authentication, Firestore/Storage provisioning, and security rules.
