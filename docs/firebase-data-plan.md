# Firebase Data Plan - Ceylon Travel

## Purpose

This document describes the planned Firebase data structure for the Ceylon Travel MVP.

The MVP app flow is:

- Tourist/user or driver creates a trip/hire post.
- Drivers can view open posts.
- Drivers submit private bids.
- The post creator accepts one bid.
- Trip chat opens.
- Trip becomes pending.
- Driver starts and ends the trip.
- User/post creator confirms start/end.
- Trip becomes completed.
- Both sides rate each other.

## Firebase Services Planned

- Firebase Authentication
- Cloud Firestore
- Firebase Storage
- Firebase Hosting later for web
- Firebase Cloud Messaging later for notifications

## Login And Registration Flow

The app uses a Login/Register split:

- Login is for existing tourists/users and drivers.
- Register is for new tourists/users and drivers.
- Firebase Authentication will be connected in Week 3.

Login form:

- phone number
- password

Unified registration form:

- full name
- phone number
- email optional
- password
- confirm password
- city / district
- account type

Account type values:

- tourist
- driver

If driver is selected, show additional fields:

- vehicle type
- vehicle number
- operating area
- available areas
- NIC / ID upload placeholder
- selfie verification placeholder

This avoids maintaining separate tourist and driver registration screens long-term.

## Collections

### users

Stores tourist/customer profile data.

Fields:

- uid
- fullName
- phoneNumber
- email
- city
- accountType
- isVerified
- averageRating
- completedTripsCount
- cancelledTripsCount
- last10TripsCancellationRate
- status
- createdAt
- updatedAt

Status values:

- active
- warning
- blocked

### drivers

Stores driver profile and verification data.

Fields:

- uid
- fullName
- phoneNumber
- email
- city
- vehicleType
- vehicleNumber
- operatingArea
- availableAreas
- nicImageUrl
- selfieImageUrl
- verificationStatus
- isVerified
- averageRating
- completedTripsCount
- cancelledTripsCount
- last10TripsCancellationRate
- status
- createdAt
- updatedAt

Verification status values:

- pending
- approved
- rejected

### trip_posts

Stores trip/hire advertisements created by tourists/users or drivers.

Drivers can create trip/hire posts when they receive a hire they cannot complete and want to pass it to other drivers.

Fields:

- id
- creatorId
- creatorType
- creatorName
- touristId optional
- driverId optional
- pickupLocationText
- dropLocationText
- tripDate
- tripTime
- adultsCount
- kidsCount
- baggageCount
- vehiclePreference
- notes
- status
- acceptedBidId
- acceptedDriverId
- createdAt
- updatedAt

Creator type values:

- tourist
- driver
- admin

Status values:

- open
- bidAccepted
- pendingTrip
- started
- completed
- cancelled
- expired

### bids

Stores driver bids for trip posts.

Important MVP rule:

Bids are private. Only the post creator should see all bids. Drivers should see only their own bid unless they created the post.

Fields:

- id
- tripPostId
- driverId
- driverName
- driverRating
- completedTrips
- cancellationRate
- vehicleType
- price
- estimatedTravelTime
- message
- status
- createdAt
- updatedAt

Status values:

- submitted
- accepted
- closed
- cancelled

### trips

Created after a post creator accepts one bid.

Fields:

- id
- tripPostId
- touristId optional
- creatorId
- creatorType
- driverId
- acceptedBidId
- acceptedBidPrice
- status
- startRequestedAt
- startConfirmedAt
- endRequestedAt
- endConfirmedAt
- cancelledBy
- cancelReason
- createdAt
- completedAt

Status values:

- pending
- startRequested
- started
- endRequested
- completed
- cancelled

Rules:

- Driver starts and ends the trip.
- User/post creator must confirm start/end within 3 minutes.
- Auto-confirm/auto-complete after 15 minutes.
- Both sides can cancel.
- Cancellations count against the account.

### chats

Stores chat summary for accepted trips.

Fields:

- id
- tripId
- creatorId
- touristId optional
- driverId
- lastMessage
- lastMessageAt
- createdAt

### messages

Stores trip chat messages.

Fields:

- id
- chatId
- senderId
- senderName
- messageType
- text
- locationLat
- locationLng
- locationMapUrl
- imageUrl
- createdAt

Message types:

- text
- location
- image
- system

Location sharing rule:

Location sharing is available only inside the accepted trip chat.

### ratings

Stores mutual ratings after completed trips.

Fields:

- id
- tripId
- fromUserId
- fromUserName
- toUserId
- toUserName
- ratingValue
- comment
- createdAt

Rule:

Rating is allowed only after trip status is completed.

### complaints

Stores complaints/reports.

Fields:

- id
- tripId
- reportedById
- reportedAgainstId
- reason
- details
- status
- createdAt
- resolvedAt

Status values:

- open
- reviewing
- resolved
- rejected

## Security Rules Idea

Initial MVP security rules should enforce:

- Tourists/users and drivers can create trip/hire posts.
- Drivers can create posts when they want to pass a hire to other drivers.
- Post creator can view bids for their own posts.
- Drivers can only see their own submitted bid unless they are the post creator.
- Chat messages are visible only to the post creator and accepted driver.
- Ratings can be created only by trip participants.
- Admin-only actions should be protected by admin role.

## Backup/Export Plan

For MVP:

- Keep Firebase data structure simple.
- Add export option later for admin.
- Export users, drivers, trips, bids, and ratings as JSON or CSV.
- Keep migration-friendly field names.
