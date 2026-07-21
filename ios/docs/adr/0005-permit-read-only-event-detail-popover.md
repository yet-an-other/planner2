# Permit a read-only Event Detail Popover on the iOS Calendar Surface

## Status

Accepted. Supersedes the Calendar Events slice's out-of-scope exclusion of "Day Events Popover, Event Detail Popover, and any event interaction, selection, or drill-through" (issue #75) and the "Date Cells remain inert" statement in the iOS calendar-surface spec.

## Context

The iOS Calendar Events slice deliberately shipped interaction-free: Date Cells inert, the Events Overflow marker inert, popovers out of scope — the iOS form of the calm-overview constraint the Web Experience had encoded in its first overlay PRD. The Web Experience resolved the same tension in web ADR [`0002-permit-read-only-event-detail-popover.md`](../../../web/docs/adr/0002-permit-read-only-event-detail-popover.md) by separating two senses of "read-only": *write-read-only* (no creating, editing, or deleting events — retained permanently) and *non-interactive* (no clicks or popups — lifted for one narrow purpose). The requirement to inspect one event's details, including a link to it in Google Calendar, now reaches the iOS Calendar Surface with explicit web-parity intent.

## Decision

The iOS Calendar Surface adopts web ADR 0002's separation unchanged:

1. The surface remains **write-read-only forever**.
2. An **Event Detail Popover** (Planning glossary) may be summoned by tapping a Calendar Event Bar or Calendar Event Row — and nothing else. Date Cells otherwise remain inert, and the Events Overflow marker stays inert.
3. The popover is presented in platform-appropriate form: a native anchored popover (adapting to a sheet on compact widths) with a small close affordance, dismissed by outside tap, that affordance, or the platform gesture — not by surface scroll. Its content and omission rules mirror the Web Experience's popover: title with an Event Color accent, a timing line, location, plain-text notes, attendees with response status as text, and a link to the event in Google Calendar.
4. All detail it presents is **memory-only while connected**, extending iOS ADR 0003's boundary from titles and timing to all event detail. An open popover closes on Disconnect on This Device as a consequence of events being cleared, not as a special case.

## Consequences

- The Google Calendar seam grows to decode event detail (Google link, location, notes, attendees) and to retain timed events' end instants for the timing line; all of it stays memory-only per iOS ADR 0003.
- The Events Overflow marker's inertness is reconfirmed by decision, not inertia: the Day Events Popover remains out of scope, and the Planning glossary's Events Overflow definition explicitly leaves summoning to each delivery experience.
- The first-connect disclosure and App Privacy posture are unchanged: detail arrives inside the same event fetches the disclosure already covers and is never persisted.

## Considered options

- **Keep the iOS surface interaction-free.** Rejected: the detail-and-link requirement is real, and web ADR 0002's separate-layer resolution preserves the calm-overview identity without opening write capabilities.
- **Also summon a Day Events Popover from the Events Overflow marker.** Rejected for this slice: a separate feature with its own design questions; the marker's inertness is deliberately reconfirmed.
- **A custom web-like overlay instead of the native popover.** Rejected: hand-rolled anchoring, clamping, dismissal, and accessibility for chrome that would feel non-native on iOS; UI-logic parity does not require chrome parity.
