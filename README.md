# Ceylon Travel MVP

Ceylon Travel is a Flutter MVP for replacing ad hoc Sri Lanka travel WhatsApp groups with a structured tourist, driver, bid, chat, trip, and rating flow.

## Current App Flow

Splash -> Welcome

The Welcome screen provides:

- Login
- Register
- View Demo Flow

Login is for existing tourists/users and drivers. Firebase authentication is not connected yet, so MVP login routes into the demo account type flow.

Register opens one unified registration form. New users choose either Tourist/User or Driver. Driver registration reveals vehicle, operating area, NIC/ID upload placeholder, and selfie verification placeholder fields.

## MVP Features

- Login/Register split
- Unified tourist/user and driver registration
- Tourist/user account type
- Driver account type
- Driver-specific verification fields
- Tourists/users can create trip posts
- Drivers can create trip/hire posts for hires they cannot complete
- Drivers can submit private bids
- Post creator can accept one bid
- Other bids close after one bid is accepted
- Private trip chat after bid acceptance
- Pending trip flow
- Completed trips
- Mutual rating system

## Development

Run the usual Flutter checks before handing off changes:

```sh
dart format lib test
flutter analyze
flutter test
```
