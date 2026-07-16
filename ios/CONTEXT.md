# iOS Experience

The iOS Experience context defines the language of Planner's event-free calendar presentation on iOS.

## Language

**iOS Calendar Surface**:
The event-free presentation of the Calendar Grid adapted for iOS conventions.
_Avoid_: iOS calendar, web calendar clone, event calendar

**iOS Calendar Header**:
The non-scrolling area above the iOS Calendar Surface that displays the Product Name, a Visible Month that acts as a Today Jump, and Monday-first weekday labels—nothing else.
_Avoid_: Navigation bar, top bar, web header

## Relationships

- **iOS Experience → Planning**: Uses Planning's Calendar Grid, Product Name, Today, Week Row, Date Cell, Extended Calendar Range, Month Marker, Visible Month, and Today Jump language.
- **iOS Experience ∥ Web Experience**: The native and web delivery stacks are peers. They share vocabulary but no executable code, packages, generated source, or build tooling.

## Delivery documentation

- [`README.md`](README.md) — standalone contributor setup and validation
- [`docs/specs/calendar-surface.md`](docs/specs/calendar-surface.md) — accepted iOS Calendar Surface behavior, exclusions, and manual acceptance
