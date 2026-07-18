# iOS Experience

The iOS Experience context defines the language of Planner's event-free calendar presentation on iOS.

## Language

**iOS Calendar Surface**:
The event-free presentation of the Calendar Grid adapted for iOS conventions.
_Avoid_: iOS calendar, web calendar clone, event calendar

**iOS Calendar Header**:
The non-scrolling area above the iOS Calendar Surface that displays the Product Name, a Visible Month that acts as a Today Jump, an iOS Account Control, an iOS Header Status, and Monday-first weekday labels.
_Avoid_: Navigation bar, top bar, web header

**iOS Account Control**:
The iOS Calendar Header control that displays the Google Account Connection state and lets the user connect or Disconnect on This Device.
_Avoid_: Login button, profile button, auth widget

**iOS Header Status**:
The single-line iOS Calendar Header area for brief progress, error, and other system messages.
_Avoid_: Toast, banner, notification bar, status bar

## Relationships

- **iOS Experience → Planning**: Uses Planning's Calendar Grid, Product Name, Today, Week Row, Date Cell, Extended Calendar Range, Month Marker, Visible Month, Today Jump, Google Authorization Grant, Google Account Connection, and Disconnect on This Device language.
- **iOS Experience ∥ Web Experience**: The native and web delivery stacks are peers. They share vocabulary but no executable code, packages, generated source, or build tooling.

## Delivery documentation

- [`README.md`](README.md) — standalone contributor setup and validation
- [`docs/specs/calendar-surface.md`](docs/specs/calendar-surface.md) — accepted iOS Calendar Surface behavior, exclusions, and manual acceptance
- [`docs/specs/google-account-connection.md`](docs/specs/google-account-connection.md) — accepted iOS Google Account Connection behavior, exclusions, compliance validation, and manual acceptance
- [`docs/adr/0001-use-google-sign-in-for-native-account-connection.md`](docs/adr/0001-use-google-sign-in-for-native-account-connection.md) — accepted native authentication boundary
- [`docs/research/google-account-connection-authentication.md`](docs/research/google-account-connection-authentication.md) — supporting primary-source authentication research
