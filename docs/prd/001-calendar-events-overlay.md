# PRD: Calendar Events on the Calendar Surface

## Problem Statement

The Calendar Surface currently shows only dates — no events, tasks, or reminders. Users connect their Google Account to The Planner but see no visual representation of their primary Google Calendar events on the surface they use for planning. They cannot see which days are occupied, where multiday commitments fall, or how their schedule shapes the week.

## Solution

Fetch Calendar Events from the user's primary Google Calendar and render them directly on the Calendar Surface. Multiday and all-day events appear as colored Calendar Event Bars spanning the Date Cells they occupy. Intraday events appear as Calendar Event Rows inside individual Date Cells, showing a dot, start time, and title. The Calendar Surface remains a passive read-only planning view.

## User Stories

1. As a connected user, I want to see my multiday Google Calendar events as colored bars spanning multiple Date Cells, so that I can quickly grasp long-running commitments.
2. As a connected user, I want to see my all-day events as colored bars inside a single Date Cell, so that I can distinguish them from timed events.
3. As a connected user, I want to see my intraday Google Calendar events inside the correct Date Cell with their start time and title, so that I can plan around them.
4. As a connected user, I want the event color to match what I see in Google Calendar, so that color-coded categories remain meaningful.
5. As a connected user, I want the bar to show the event title starting from its first day and continuing across all days it spans, so that I can identify it at any scroll position.
6. As a connected user, I want overlapping multiday bars to stack vertically in separate lanes so both titles remain readable, rather than one obscuring the other.
7. As a connected user with many events on a single day, I want the Calendar Surface to cap visible items and show a `+N events` indicator, so that the Date Cell never overflows the fixed Week Row height.
8. As a connected user, I want declined events and cancelled events to not appear on the Calendar Surface, so that I only see events I am actually attending.
9. As a connected user, I want the Calendar Surface to fetch events around my visible area with a buffer, so that scrolling is smooth and I don't wait for data on every small scroll.
10. As a connected user, I want the event text to remain readable regardless of the Google Calendar color (light or dark), so that I don't have to squint at low-contrast text.
11. As a user who disconnects their Google Account Connection, I want the Calendar Surface to fall back to Saved Busy Blocks without titles, so that my planning shape is preserved without exposing private event details.
12. As a user, I want events that cross midnight (e.g., 23:00–01:00) to be treated as multiday bars rather than intraday rows, so that the visual model is consistent: bars cross Date Cell boundaries, rows do not.
13. As a connected user scrolling through the Extended Calendar Range, I want events to appear as soon as the slab containing them is cached, and not require re-fetching when I scroll back, so that the experience feels snappy.
14. As a connected user, I want multiday bars to be ordered by start date, then start time, then duration (longer first), so that the visual stacking is deterministic and predictable.
15. As a connected user, I want intraday rows to be ordered by start time within their Date Cell, so that the chronological sequence is preserved.
16. As a user with a dense calendar, I want the 4-item cap to apply to the combined total of bars and rows within each Date Cell, so that the layout stays compact and readable.
17. As a user, I want the Calendar Surface to remain read-only — no clicks, popups, or interactions on events — so that the surface stays calm and focused on overview.
18. As a user, I want the Calendar Surface height per Week Row to remain fixed at 128px regardless of event density, so that scrolling position and virtual rendering stay stable.

## Implementation Decisions

- **Event Layout Engine** (new deep module): A pure function that accepts an array of Calendar Events and a visible week range, and returns per-Date Cell render instructions. This module encapsulates the entire complexity of: (a) partitioning events into Bars (multiday / all-day / midnight-crossing) and Rows (intraday within a single Date Cell); (b) assigning Bars to vertical lanes per week with deterministic ordering (start date → start time → longer duration first); (c) capping each Date Cell to 4 visible items (combined bars + rows) with an overflow count; (d) computing which cells each Bar's title must be rendered in for continuity across spanned Date Cells. The interface is intentionally narrow: `layoutEvents(events, weekStartDate) => WeekLayout`.

- **Slab Cache** (new module): Google Calendar Events are fetched and cached in discrete 3-month slabs (e.g., Q1, Q2). A slab is fetched from the Google Calendar API with `timeMin` / `timeMax` set to slab boundaries. The cache keeps the visible slab plus adjacent slabs in memory (providing the effective 6-month buffer). Fetching is triggered on initial connection and when scrolling reveals a week not covered by cached slabs. Cache eviction is simple: LRU or fixed-size ring. This module isolates all API pagination, caching, and cache-hit logic from the Calendar Surface component.

- **Text Contrast Utility** (new small module): Computes luminance of a hex color and returns either black (`#000000`) or white (`#FFFFFF`) text color to ensure readability on any Google Calendar event color. Simple threshold-based implementation (e.g., YIQ or relative luminance).

- **Google Calendar Events module** (modify existing): The existing `google-calendar-events` module already handles event fetching, normalization, declined/cancelled filtering, and color resolution. Minor modifications may be needed to expose a slab-aware fetch interface (fetch by explicit start/end boundaries rather than a single large range). The existing `CalendarEvent` union type (`CalendarEventBar | CalendarEventRow`) already matches our domain model.

- **Calendar Surface component** (modify existing): Integrates the Slab Cache, Event Layout Engine, and rendering. On `googleAccountConnection` becoming `connected`, triggers initial slab fetch. On scroll, checks whether visible weeks are covered by cached slabs and fetches missing ones. Passes fetched events through the Layout Engine and renders the resulting Bars (as absolutely positioned or grid-spanned elements depending on CSS strategy) and Rows inside each Date Cell. The component continues to use TanStack Virtual for Week Row virtualization with the fixed 128px height.

- **Saved Busy Blocks** (no change): ADR 0001 remains in force. When the Google Account Connection is disconnected, the Calendar Surface renders Saved Busy Blocks (title-less placeholders with timing and color). The existing `saved-busy-blocks` module and persistence logic require no modification.

- **Rendering strategy for Bars**: Because Bars span multiple Date Cells and must show their title continuously across them, each Bar is rendered as a single positioned element within the Week Row (using absolute positioning with left/width derived from Date Cell indices) rather than as per-cell fragments. This ensures text truncation and overflow behave correctly across cell boundaries. Rows are rendered inside individual Date Cell containers.

- **Rendering strategy for the 4-item cap**: Per Date Cell, the Layout Engine produces an ordered list of up to 4 render items (Bars in their assigned lanes, followed by Rows) plus an optional overflow indicator. The Calendar Surface component renders exactly what the engine produces. No additional truncation logic lives in the component.

- **Fetch window behavior**: Events that started before the fetch window but end within it will not be fetched (Google Calendar API `timeMin` filters by start time). This is an acknowledged limitation; supporting ongoing events that predate the window is out of scope.

## Testing Decisions

- **What makes a good test**: Tests verify external behavior and output, not internal algorithms. For the Layout Engine, tests pass in arrays of Calendar Events and assert on the resulting WeekLayout (which lanes bars occupy, which rows appear, where overflow is reported, title continuity). For the Slab Cache, tests stub the fetch function and assert on cache-hit behavior, deduplication, and fetch triggering.

- **Modules to test**:
  - **Event Layout Engine** — highest priority, most complexity. Comprehensive unit tests covering lane assignment, ordering, capping, overflow, and title continuity.
  - **Slab Cache** — unit tests for cache hits/misses, boundary conditions at slab edges, and deduplication of overlapping fetches.
  - **Text Contrast Utility** — simple unit tests for light and dark input colors.
  - **Google Calendar Events normalization** — existing behavior, but verify that single-day all-day events emit `CalendarEventBar` with matching start/end dates, and that midnight-crossing timed events emit `CalendarEventBar` (not `CalendarEventRow`).

- **Prior art**: `calendar-surface.test.tsx` already contains component-level tests for Google Account Connection using Testing Library and Vitest. The new tests should follow the same patterns: stub network calls, render components, and assert on visible content.

## Out of Scope

- Auto-refreshing events on a timer (events do not poll; refresh requires reconnect or scroll)
- Click interaction, event details popup, or any interactivity on Calendar Events
- Variable Week Row height based on event density (height remains fixed at 128px)
- Events that started before the fetch window but overlap into it (acknowledged limitation)
- Duration display on Calendar Event Rows (only start time + title)
- Creating, editing, or deleting events (read-only view)
- Secondary or shared Google Calendars (only primary calendar)
- Recurring event expansion logic (Google API handles this via `singleEvents=true`)

## Further Notes

- The existing `WEEK_ROW_HEIGHT = 128` is preserved. The Layout Engine must never produce more than 4 items per Date Cell to maintain this invariant.
- `singleEvents=true` is already used in the Google Calendar API request, so recurring events are returned as expanded individual instances.
- The `+N events` overflow indicator replaces the 4th slot when there are more than 4 items. It is not an additional 5th line.
- The visual distinction between Bar and Row is the primary sorting key. Bars always sort before Rows within a Date Cell, regardless of start time.
