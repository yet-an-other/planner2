# Persist the Selected Source Calendars per device

## Status

Accepted.

## Context

The Planner is a browser SPA with no backend; until now it has had no persistence of any kind. Users will configure their Selected Source Calendars once and expect the choice to survive a page refresh or a reconnect. Because the Source Calendar list is loaded eagerly on connect (so the connect path can fetch from the right calendars immediately), a memory-only selection would silently reset to the `[primary]` default on every reload — a poor experience for a setting people set once.

## Decision

Persist the Selected Source Calendars in `localStorage` as a JSON array of Google calendar `id`s, keyed per Google account (e.g. `planner.sourceCalendars.<email>`). On connect, read the stored ids, intersect them with the eagerly-fetched calendar list (dropping ids that were deleted or are no longer readable), and use the intersection as the Selected Source Calendars. If the intersection is empty, fall back to `[primary]`.

## Consequences

- **Per-device, not per-account.** A user who configures their calendars on one laptop must reconfigure on another device or browser. A backend would fix this, but The Planner has none. This limitation is accepted for now.
- **This is the codebase's first persistence**, and it sets the precedent that Saved Busy Blocks (ADR 0001, not yet implemented) will likely follow.
- Stored ids are reconciled against the live calendar list on every connect, so deleted or revoked calendars are pruned automatically.

## Alternatives considered

- **Memory-only.** Rejected: with eager loading, the selection resets to `[primary]` on every reload.
- **Server-side, per Google account.** Rejected: The Planner has no backend, and introducing one for this setting is out of scope for the first slice.
