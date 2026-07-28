# Keep iOS Calendar Events memory-only, with no offline placeholders

## Status

Superseded by [ADR 0007](0007-persist-stored-calendar-events.md), which persists full Calendar Events as Stored Calendar Events. At acceptance: ADR 0006 narrows this decision's broader data-persistence language for Selected Source Calendar configuration; Calendar Events remain memory-only.

## Context

The Web Experience persists **Saved Busy Blocks** — privacy-preserving placeholders retaining a Calendar Event's timing and color but not its title — so its disconnected or offline Calendar Surface keeps the shape of the user's schedule (web ADR [`0001-persist-saved-busy-blocks-without-event-titles.md`](../../../web/docs/adr/0001-persist-saved-busy-blocks-without-event-titles.md)). When Calendar Events came to the iOS Calendar Surface, the same offline question arose. The iOS Google Account Connection slice had already set a strict data-minimization stance: Planner persists no access tokens, profile fields, or Calendar data, and its App Privacy posture reflects that.

## Decision

The iOS Experience keeps Calendar Events strictly memory-only. Events are fetched from Google per process run, retained only in memory while the process lives, and never written to disk, Keychain, or backups. A disconnected surface, or a fresh process whose initial fetch cannot run offline, presents the bare Calendar Grid with a message in the iOS Header Status — no Busy-Block-style placeholders. Calendar Events already fetched in the current process remain visible through a later offline period. This deliberately diverges from the Web Experience's persisted Saved Busy Blocks.

## Consequences

- Planner's iOS data-minimization stance and App Privacy answers can continue to state that no Calendar Events, event details, or event-derived offline placeholders are stored. ADR 0006 separately permits account-linked Selected Source Calendar IDs and requires the disclosure and privacy review appropriate to that configuration.
- Ranges that were never fetched while offline appear empty; already-fetched in-memory events remain visible until the process ends.
- The Web and iOS experiences now differ in offline event presentation by decision, not by omission — future parity work must revisit this ADR explicitly.

## Considered options

- **Persist Saved Busy Blocks for iOS (web parity).** Rejected: adds Calendar-data persistence against the established data-minimization stance, enlarges the first Calendar-data slice, and changes the App Privacy story for a placeholder whose value is lowest on a mobile device that is frequently relaunched.
- **Persist full Calendar Events for offline fidelity.** Rejected more strongly: stores event titles and details on device with no corresponding product need in this slice.
