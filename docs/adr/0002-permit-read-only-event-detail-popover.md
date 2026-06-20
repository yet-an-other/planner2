# Permit a read-only Event Detail Popover summoned from the Calendar Surface

## Status

Accepted. Supersedes the "read-only / no popups" portions of PRD #001 (User Story #17 and the Out-of-Scope item "Click interaction, event details popup, or any interactivity on Calendar Events").

## Context

PRD #001 deliberately made the Calendar Surface **non-interactive**: no clicks, no popups, no interactivity on events, so that the surface would stay calm and focused on overview. This was encoded as User Story #17 and reinforced in the PRD's Out-of-Scope list.

A subsequent requirement asks for the ability to open an event's detail (including a link to that event in Google Calendar) by clicking on it. On its face this contradicts the documented constraint. Resolving it required separating two senses of "read-only" that PRD #001 conflated:

- **Write-read-only** — the user cannot create, edit, or delete events.
- **Non-interactive** — no clicks, popups, or any input on the surface.

The original *intent* behind the constraint was almost certainly the first (calm overview, no editing), not an absolute ban on ever clicking anything.

## Decision

We **retain the write-read-only invariant permanently** and **lift the non-interactive ban for one narrow purpose**: a transient, read-only **Event Detail Popover** that is *summoned from* the Calendar Surface but is a *separate layer* from it.

Concretely:

1. The Calendar Surface remains **write-read-only forever**. Creating, editing, or deleting events is out of scope for the product's first slice and for this decision.
2. A new **Event Detail Popover** may be summoned by clicking (or keyboard-activating) a Calendar Event Bar or Calendar Event Row. It presents the event's detail and a link to that event in Google Calendar.
3. The popover is a **separate layer**, not part of the Calendar Surface: it is rendered via a portal, is non-modal (no backdrop, no focus trap), and is dismissed by close button, Escape, outside-click, or surface-scroll.
4. The popover is **connected-only**. It cannot be summoned from Saved Busy Blocks, and an open popover closes immediately if the Google Account Connection is disconnected.
5. The popover carries **no new persistence**: all detail it displays is memory-only while connected. This is consistent with ADR 0001's principle that event titles and other event details stay memory-only and that Saved Busy Blocks carry timing and color only.

## Consequences

- PRD #001 User Story #17 and the Out-of-Scope popup line are superseded. PRD #001 is annotated accordingly.
- The Calendar Surface's calm-overview identity is preserved: the surface is calm by default; detail access is an intentional, separate act via a non-modal layer.
- A new enriched data path is introduced (the `CalendarEvent` model gains a nested `EventDetail` block). This detail is memory-only and never persisted, extending ADR 0001's privacy boundary from "titles" to "all event detail."
- The Event Layout Engine is untouched; interaction is a concern of the triggers and the popover, not the layout.

## Alternatives considered

- **Make the Calendar Surface fully interactive** (editing, drag-to-reschedule, etc.). Rejected: erodes the one thing that distinguishes this product from every other calendar app, and is far beyond the stated requirement.
- **Disallow the popover; honor the original non-interactive constraint.** Rejected: the detail-and-link requirement is real and the non-modal, separate-layer resolution satisfies it without sacrificing the calm-overview identity.
- **Modal popover with backdrop and focus trap.** Rejected: turns a glance-at-detail action into an interruption, contradicting the calm-overview identity. A non-modal, portal-rendered layer is the chosen balance.

## References

- PRD #001 — Calendar Events on the Calendar Surface (superseded items annotated).
- PRD #003 — Event Detail Popover (the feature spec enabled by this decision).
- ADR 0001 — Persist Saved Busy Blocks without event titles (the privacy principle extended here from titles to all event detail).
