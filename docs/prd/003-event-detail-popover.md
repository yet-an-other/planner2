# PRD: Event Detail Popover

## Problem Statement

The Calendar Surface displays Calendar Events as bars and rows, but a bar or row carries only a title, a color, and minimal timing. When a user wants the full picture of an event — where it is, who's invited, what the notes say, or a direct link to the event in Google Calendar — there is no way to get it from the surface. The user must leave the product, open Google Calendar, and locate the event manually. The surface conveys *shape* but not *detail*.

PRD #001 deliberately made the Calendar Surface non-interactive. ADR 0002 revises that constraint narrowly: the Calendar Surface remains write-read-only forever, but a transient, read-only **Event Detail Popover** may be summoned to show an event's detail. This PRD specifies that popover.

## Solution

Add a separate, non-modal **Event Detail Popover** layer that is summoned by clicking (or keyboard-activating) a Calendar Event Bar or Calendar Event Row. The popover is rendered via a portal outside the Calendar Surface's virtualized scroll container, positioned near the trigger, and dismissed by a close button, the Escape key, an outside click, or any scroll of the surface.

The popover reads its detail from the existing in-memory `CalendarEvent`. The `CalendarEvent` model is enriched with a nested `EventDetail` block (link, location, description, attendees) and a normalized `EventTiming`, all computed at normalization time from data already returned by the Google Calendar `events.list` endpoint. No new network call is made when the popover opens.

The popover is connected-only: it cannot be summoned from Saved Busy Blocks, and an open popover closes immediately if the Google Account Connection is disconnected. All detail it displays is memory-only and never persisted, extending ADR 0001's privacy principle from titles to all event detail.

## User Stories

1. As a connected user, I want to click a Calendar Event Bar or Row to open a popover with that event's detail, so that I can read more than the title without leaving the surface.
2. As a connected user, I want a keyboard way to open and close the popover, so that I am not dependent on a mouse.
3. As a connected user, I want a link in the popover that opens the event directly in Google Calendar, so that I can take action (RSVP, join, edit) in the source system.
4. As a connected user, I want to see the event's location in the popover, so that I know where I need to be.
5. As a connected user, I want to see the event's description/notes in the popover, so that I have the context the organizer provided.
6. As a connected user, I want to see who is invited and their response status, so that I know who else is involved and whether they've accepted.
7. As a connected user, I want only one popover open at a time, so that the surface stays calm and I am not overwhelmed by stacked detail panels.
8. As a connected user, I want the popover to close when I scroll the surface, so that a stale, orphaned popover never floats over the wrong part of the calendar.
9. As a connected user, I want the popover to open instantly, so that I never wait on a network round-trip to read event detail I've already scrolled to.
10. As a connected user, I want the popover to omit empty fields rather than show placeholders, so that a sparse event still looks clean and intentional.
11. As a connected user, I want the popover to respect the product's visual identity (warm parchment/olive palette), so that it feels like part of the product and not a third-party widget.
12. As a user who disconnects their Google Account Connection while a popover is open, I want the popover to close immediately, so that no event detail is shown in the disconnected state.
13. As a user viewing the disconnected Calendar Surface (Saved Busy Blocks), I want no popover to be summonable, so that the privacy-preserving placeholder state is not circumvented.
14. As a screen-reader user, I want the popover to be a properly labelled, non-modal dialog with predictable focus management, so that I can read event detail and return to the surface.
15. As a low-vision or color-blind user, I want attendee response status conveyed as text, not color alone, so that I can tell who has accepted or declined.

## Implementation Decisions

- **Enriched `CalendarEvent` model** (modify existing): The `CalendarEventBar` and `CalendarEventRow` types each gain a nested `detail: EventDetail` block, plus a normalized `timing: EventTiming` computed at normalization time. The `EventDetail` block is `{ htmlLink: string | null; location: string | null; description: string | null; attendees: Attendee[] }`. `EventTiming` is a uniform display shape (e.g. `{ startDate, endDate, isAllDay, isMultiday }`) derived once during normalization from the bar's `date`/`endDate` or the row's `date`/`startTime`/`durationMinutes`, so the popover never branches on `kind`. Optional string fields are `string | null` (null = "Google returned no value"); `attendees` is always an array (possibly empty); `responseStatus` is a closed union (`'accepted' | 'declined' | 'tentative' | 'needsAction' | 'unknown'`) with unknown values collapsing to `'unknown'`.

- **Normalization source** (modify existing `google-calendar-events.ts`): `normalizeGoogleCalendarEvents` stops discarding the detail fields. The Google Calendar `events.list` response already includes `htmlLink`, `location`, `description`, and `attendees[]` for every event; we carry them through into the `EventDetail` block. HTML in `description` is stripped and rendered as plain text. Attendees are mapped to the closed-union `responseStatus`. No new network call is required; we are retaining data we already fetch and currently drop.

- **`<EventDetailPopover>`** (new presentational component, `src/components/event-detail-popover.tsx`): Pure/presentational. Props: `{ event: CalendarEvent | null; anchorRect: DOMRect | null; onClose: () => void }`. Renders nothing when `event` is null. Renders a portal to `document.body`, a `role="dialog"` / `aria-modal="false"` container labelled by the event title, the title, the timing, any present optional fields (location, description, attendees), and the "Open in Google Calendar" link. Zero state, zero effects, zero fetches. Tested in isolation.

- **`useEventDetailPopover()`** (new state hook, `src/lib/use-event-detail-popover.ts`): Owns the popover lifecycle. Returns `{ selectedEvent, anchorRect, open(event, triggerEl), close() }`. Owns: which event is selected, the anchor rect captured at open time, and the close-on-surface-scroll and close-on-disconnect wiring. Subscribes to the surface's scroll container ref and to the connection status to fire `close()`. Symmetric with the existing `useGoogleAccountConnection` and `useCalendarEvents` hooks.

- **Triggers** (modify existing renderers): Calendar Event Bars and Rows render as native `<button>` elements with descriptive accessible names (e.g. *"Dentist, June 19, 9:00 AM — open details"*). Click or Enter/Space calls `open(event, triggerEl)`. The trigger's `aria-expanded` reflects whether its popover is open. The `+N events` overflow indicator and Saved Busy Blocks are **not** interactive.

- **Rendering placement**: The popover renders through a portal to `document.body` so it is never a child of a virtualized Week Row that TanStack Virtual can unmount. Position is `position: fixed`, computed from the trigger's `getBoundingClientRect()` captured at open time. Placement prefers below the trigger, flips above when there is no room, and clamps to the viewport edges. Because the popover closes on surface scroll, the captured rect never goes stale; no anchor-tracking listeners are required. A single `<EventDetailPopover>` instance at the Calendar Surface root is reused for any trigger (single cardinality).

- **Calendar Surface** (modify existing): Stays a thin orchestrator. It composes `useGoogleAccountConnection`, `useCalendarEvents`, and `useEventDetailPopover`; passes the `open` callback into the bar/row renderers; and renders `<EventDetailPopover>` once at the root. It owns no popover state itself.

- **Lifecycle rules**: At most one popover open at a time; opening a second event replaces the first. Dismiss by: close button, Escape key, outside click, or any surface scroll. On open, focus moves to the close button; on close, focus returns to the trigger. No backdrop, no focus trap (the dialog is non-modal; Tab can leave it).

- **Privacy**: All `EventDetail` fields are memory-only while connected and never persisted, logged, or sent over the network by the popover. The only outbound action is the user-clicked `htmlLink`. Saved Busy Blocks carry none of the detail. This extends ADR 0001's privacy boundary from titles to all event detail.

- **Visual treatment**: The popover reuses the product's existing parchment/olive palette (`#f5f1e6` background, `#252819` primary text, `#777b60`/`#8b8f72` muted text, `#d8d1bd` border). The event's own color is the single chromatic accent (a left stripe or chip beside the title). Width `min(360px, 90vw)`; height content-driven with `max-height: 80vh` and internal scroll for long descriptions. Soft shadow and modest border radius. Compact attendee rows (no avatars). No backdrop. Optional quick fade-in (`duration-150`).

## Testing Decisions

- **Direct unit tests for enriched normalization** (new `src/test/lib/google-calendar-events.test.ts`): covers `normalizeGoogleCalendarEvents` with the enriched detail — `htmlLink`/`location`/`description` carried through, attendees mapped to the closed union with unknown-collapse, timing normalized into `EventTiming` for both bar and row, empty/missing fields → `null`/empty array, declined/cancelled filtering preserved. This also closes a pre-existing coverage gap (normalization was previously only exercised transitively).

- **Direct unit tests for the display-shape accessor** (`toEventDetail` / timing normalization, if extracted as a pure function): bar → `EventTiming`, row → `EventTiming`, all-day vs multiday, midnight-crossing edge cases.

- **Component test for `<EventDetailPopover>`** (`src/test/components/event-detail-popover.test.tsx`): renders title/timing/location/description/attendees; omits null rows; shows "No attendees" for an empty array; renders `htmlLink` when present and omits when null; truncates attendees at 5 with "+N more"; close button calls `onClose`; has `role="dialog"` + `aria-labelledby`; the "Open in Google Calendar" link has `target="_blank" rel="noopener noreferrer"`; long description renders in a scrollable region.

- **Integration tests at the Calendar Surface level** (extend `src/test/components/calendar-surface.test.tsx`): clicking a bar/row opens the popover for the right event; clicking a second swaps (single cardinality); outside-click, Escape, and Close all dismiss; opening then scrolling the surface closes it; the disconnected state renders non-interactive bars/rows with no summonable popover; close-on-disconnect (open then disconnect → closes).

- **Positioning math is not unit-tested**: `getBoundingClientRect` + flip/clamp is DOM-coupled and unreliable in jsdom. We assert only the contract (portal target is `document.body`; the popover has `position: fixed`; it consumes the passed anchor rect). Real visual placement is a manual/visual check.

## Out of Scope

- Creating, editing, or deleting events (the Calendar Surface remains write-read-only forever — ADR 0002).
- A second outbound link for conference/Join-via-Meet (`conferenceData` / `hangoutLink`); v1 ships one outbound link (`htmlLink`).
- Rich/HTML rendering of `description`; v1 renders plain text only.
- Hover-to-preview; the popover is summoned by click/keyboard, not revealed on hover.
- A mobile bottom-sheet mode; v1 uses the same floating popover on all viewports.
- Attendee avatars/photos; v1 renders names/emails + status only.
- Multiple open popovers; v1 is single-cardinality.
- Lazy per-open fetching of event detail (Approach A — enriched in-memory model — is chosen; no `GET /events/{id}` on open).
- Persisting any `EventDetail` field into Saved Busy Blocks or any offline store (memory-only, per ADR 0001/0002).
- E2E tests and snapshot tests for the popover.
- Any change to the Event Layout Engine (`event-layout.ts` is untouched).

## Further Notes

- Because the popover reads from the in-memory `CalendarEvent[]` that scroll-driven fetching already maintains, and because that array is deduplicated by event ID across overlapping slabs (PRD #002), the popover always reflects the canonical, deduplicated event even if it was fetched by multiple racing slab requests.
- The close-on-surface-scroll rule is coupled to TanStack Virtual virtualization: a popover anchored to a Week Row that scrolls out of view would otherwise float over an unmounted anchor. Closing on scroll is simpler and more predictable than re-anchoring, and keeps the surface primary.
- Timing normalization lives at the normalization source so the popover sees one uniform `EventTiming` shape regardless of bar-vs-row. This keeps the popover free of `kind`-branching and keeps the "interface is the test surface" property for both the normalization module and the popover component.
- Attendee display is name-primary, email-fallback: show the display name when present; show the email only when there is no display name. Response status is always rendered as text (or icon + text), never color alone, for both accessibility and consent/privacy clarity.
- References: ADR 0002 (the decision that permits this feature); ADR 0001 (the privacy principle this feature extends); PRD #001 (the surface this feature is summoned from); PRD #002 (the fetch model whose in-memory events the popover reads).
