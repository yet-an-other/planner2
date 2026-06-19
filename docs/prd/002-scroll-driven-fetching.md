# PRD: Scroll-Driven Fetching of Calendar Events

## Problem Statement

The Calendar Surface currently fetches a single ±6-month window of Calendar Events when the Google Account Connection becomes active. As the user scrolls beyond that fixed window into earlier or later parts of the Extended Calendar Range, no events appear. The user must disconnect and reconnect to refresh the data, and there is no mechanism to load events for dates outside the initial window.

## Solution

Replace the single static fetch with **boundary-driven slab fetching**. The Calendar Surface maintains a **Fetched Window** that starts at the initial ±6-month range and expands automatically as the user scrolls. When the visible area of the Calendar Surface comes within one month of either edge of the Fetched Window, a new 3-month slab is fetched in that direction, merged into the existing event set, and the Fetched Window is extended. A brief "Loading events…" message appears in the Header Status while a fetch is in flight.

## User Stories

1. As a connected user, I want to scroll into next year and see my Google Calendar events appear, so that I can plan ahead without reconnecting my account.
2. As a connected user, I want to scroll into the past and see historical events, so that I can review what happened on any date in the Extended Calendar Range.
3. As a connected user, I want events to load automatically as I scroll, without clicking anything, so that the Calendar Surface feels seamless and responsive.
4. As a connected user, I want the Calendar Surface to avoid re-fetching the same date range repeatedly, so that network usage stays reasonable and the surface remains snappy.
5. As a connected user, I want a brief loading indicator when new events are being fetched while scrolling, so that I know data is on its way rather than assuming the calendar is empty.
6. As a connected user with a busy calendar, I want scroll-driven fetching to keep working even if one request fails, so that a temporary network error does not break the entire planning view.
7. As a connected user, I want events that I have already seen to stay visible when I scroll back, so that the Calendar Surface feels like a continuous surface rather than a slide deck.
8. As a connected user, I want to scroll all the way to the ten-year edges of the Extended Calendar Range and still have events load, so that the full range is usable for long-term planning.
9. As a user who disconnects their Google Account Connection, I want the Fetched Window to reset and events to clear, so that privacy is preserved and reconnecting starts fresh.
10. As a user who reconnects their Google Account Connection, I want the Calendar Surface to start from a fresh ±6-month fetch centered on Today, so that I always see the most current data after reconnecting.
11. As a connected user scrolling rapidly, I want the Calendar Surface to remain responsive even if multiple fetches are in flight, so that scrolling never blocks on network I/O.
12. As a connected user, I want new Calendar Events fetched while scrolling to be deduplicated against events I already see, so that I never see the same event twice.
13. As a connected user, I want the Fetched Window to expand only in the direction I am scrolling, so that fetching stays predictable and does not waste quota on areas I am not exploring.
14. As a developer, I want the scroll-trigger logic to be a pure, testable function disconnected from React effects, so that edge cases (e.g., trigger exactly on the boundary) can be validated without a browser.

## Implementation Decisions

- **Fetched Window** (new small module): A state object that tracks only two dates — `earliestFetched` and `latestFetched` — representing the continuous date range that has been fetched from Google Calendar. It exposes a single operation: `extend(direction, months)` which moves the corresponding boundary forward or backward by the slab size (3 months). This is intentionally minimal; it is not a slab registry, a cache, or a timeline of past fetches. The Fetched Window is reset to the initial ±6-month range on every (re)connect.

- **Scroll Trigger Detector** (new deep module): A pure function that accepts the current visible date (derived from `topWeekIndex`) and the Fetched Window, and returns one of three outcomes: `fetch-past`, `fetch-future`, or `no-op`. It computes the visible date from the virtualizer's top visible week and checks whether that date falls within one month of `earliestFetched` or `latestFetched`. Keeping this pure makes it trivial to unit-test boundary conditions (exactly on the trigger, one day before, one day after) without mounting a component.

- **Event Merge Strategy**: New slabs are merged into the existing flat `CalendarEvent[]` array by deduplicating on the Google Calendar event ID. This avoids any slab-cache data structure. The merge is a simple functional reducer: `[...existingEvents, ...newEvents].filter((e, i, arr) => arr.findIndex(x => x.id === e.id) === i)`. This trades CPU for simplicity and keeps the data model identical to what the Event Layout Engine already consumes. Because the deduplication is deterministic by ID, overlapping slab fetches are absorbed silently.

- **Google Calendar Events module** (modify existing): The existing `fetchPrimaryCalendarEvents(accessToken, range)` already accepts an arbitrary start/end range. No structural changes are required — the Clock Surface will simply invoke it with 3-month boundaries instead of the current 6-month boundary. Pagination via `nextPageToken` must be handled inside this module if a 3-month slab exceeds the API's page size.

- **Calendar Surface component** (modify existing): Integrates the Scroll Trigger Detector into the scroll handler. On every scroll event (or via a throttled scroll callback), it maps the virtualizer's `topWeekIndex` to a date, checks the detector, and conditionally triggers a fetch. While a fetch is in flight, it sets Header Status to `{ message: 'Loading events…', tone: 'info' }`. On fetch success, it merges the new events into the existing array, extends the Fetched Window, and clears the loading status. On fetch failure, it leaves the Fetched Window unchanged and clears the loading status so the next scroll into the same trigger zone will retry.

- **No concurrency control**: Multiple overlapping fetches are allowed to race. There is no abort logic, no request queue, and no debounce. The Calendar Surface simply fires a fetch whenever the detector says to, merges whatever arrives, and deduplicates by ID. This is the simplest possible implementation and aligns with the user's preference for minimal complexity over API-quota conservation.

- **Disconnect / reconnect behavior**: On disconnect, `events` is cleared and the Fetched Window is reset to `null` (or equivalent empty state). On reconnect, the Fetched Window is initialized to the initial ±6-month range centered on Today, a fetch is fired for that range, and the event array is populated fresh. No attempt is made to preserve previously fetched events across reconnections.

## Testing Decisions

- **Scroll Trigger Detector** — highest priority. Unit-test the pure function with pinned dates. Cover: (a) visible date well inside the window → no-op; (b) visible date exactly 1 month from edge → fetch; (c) visible date past the edge → fetch; (d) window is `null` / uninitialized → no-op; (e) Extended Calendar Range boundary reached → no-op (the Fetched Window cannot expand beyond the Calendar Surface's own bounds).

- **Fetched Window** — unit-test boundary arithmetic. Cover: extending pastward, extending futureward, reset on reconnect, and clamping to the Extended Calendar Range.

- **Calendar Surface integration** — component-level test using Vitest + Testing Library. Stub `fetchPrimaryCalendarEvents` to resolve with a delayed promise. Assert: (a) scroll into the trigger zone fires the stub; (b) the Header Status shows "Loading events…" while the promise is pending; (c) resolved events appear in the DOM; (d) scrolling back into the same trigger zone does not fire a second stub if the visible date is still within the updated window.

## Out of Scope

- Slab-level caching or registry (e.g., a Map keyed by `YYYY-MM`). The design intentionally uses a flat event array and simple extent tracking.
- Request cancellation, throttling, or rate-limiting. Overlapping fetches race.
- Prefetching adjacent slabs before the user scrolls into them.
- Caching fetched events in `localStorage`, IndexedDB, or any offline persistence. Events are memory-only while the Google Account Connection is active.
- Updating or refreshing existing events in place (no poll/auto-refresh).
- Any change to the Event Layout Engine, the Saved Busy Block fallback, or the read-only policy of the Calendar Surface.

## Further Notes

- The Fetched Window and the Extended Calendar Range share the same boundary semantics (Monday-first weeks). The Scroll Trigger Detector should work with `Date` objects at local midnight to avoid timezone edge cases.
- Because overlapping slab fetches are absorbed by ID-based deduplication, a user scrolling back and forth across the same boundary will trigger redundant fetches but will never end up with duplicate events in the UI.
- The Google Calendar API `timeMin`/`timeMax` params should use inclusive start and exclusive end boundaries per slab to avoid off-by-one-day issues at slab edges.
