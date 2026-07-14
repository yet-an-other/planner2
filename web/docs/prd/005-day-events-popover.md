# PRD: Day Events Popover

## Problem Statement

When a Date Cell holds more Calendar Events than the fixed Week Row height can show, the Calendar Surface caps the visible items and displays an **Events Overflow** indicator (today, a static "+N events" line). The user can see that more events exist on that day, but cannot see *what* they are: the titles, times, and any multiday bars that didn't fit are permanently clipped. To find them, the user must leave the product, open Google Calendar, and navigate to that day. The surface conveys that a day is busy, but not what makes it busy beyond the first few items.

## Solution

Make the **Events Overflow** ("+N more") a trigger that summons a new, separate-layer **Day Events Popover**: a transient, non-modal list of *every* Calendar Event attributed to that Date Cell — both the items already visible in the cell and the ones that were clipped. The list mirrors the cell's own ordering and item appearance (Calendar Event Bars in lane order, then Calendar Event Rows by start time), behind a date header. Selecting an event in the list opens the existing **Event Detail Popover** for it.

The Day Events Popover is a **layout-overflow reveal**, not a detail reveal: it shows only what the Calendar Surface already presents (clipped to the cap), so it carries no privacy boundary of its own and is **not** connection-gated. The privacy boundary continues to live on the connected-only Event Detail Popover; the drill-through from a list item to detail is the only connection-gated part. This PRD implements ADR 0004, which extends ADR 0002's separate-layer pattern to a second sibling overlay.

## User Stories

1. As a connected user with a busy day, I want to click the "+N more" indicator in a Date Cell to see a list of every event on that day, so that I am not limited to the few items that fit in the cell.
2. As a connected user, I want the list to include the events that were already visible in the cell as well as the clipped ones, so that I see the complete day in one place.
3. As a connected user, I want multiday/all-day Calendar Event Bars that pass through that day to appear in the day's list, so that spanning commitments are not hidden just because they also occupy other days.
4. As a connected user, I want the list ordered the same way the cell is ordered — all-day/multiday bars first, then timed rows by start time — so that the popover feels like an expanded view of the cell I clicked.
5. As a connected user, I want each timed row in the list to show its colored dot, start time, and title, matching the cell, so that I recognize events at a glance.
6. As a connected user, I want each bar in the list to show its color and title plus a clear "All day" or date-span label, so that I can tell it is a spanning event rather than a timed one.
7. As a connected user, I want to click an event in the list to open that event's detail (the Event Detail Popover), so that I can read location, attendees, notes, and the Google Calendar link without re-finding the event on the surface.
8. As a connected user, I want only one overlay open at a time, so that opening a day list closes any open event detail, and opening a detail closes the day list.
9. As a connected user, I want to re-open the day list easily after viewing an event's detail (by clicking "+N more" again), so that browsing several events is a series of quick glances rather than a stacked workspace.
10. As a connected user, I want the Day Events Popover to close when I scroll the Calendar Surface, so that a stale list never floats over the wrong day.
11. As a connected user, I want to close the Day Events Popover with a close button, the Escape key, or a click outside it, so that dismissal is predictable and fast.
12. As a connected user, I want the popover to open instantly with no network call, so that reading the day's events never makes me wait.
13. As a connected user, I want the popover to show the full date (weekday, month, day, year) in a header, so that I am certain which day I am looking at.
14. As a connected user, I want the "+N more" count to reflect the number of events hidden beyond the visible cap, so that the number is honest about why it appears.
15. As a connected user, I want the trigger to read "+N more" rather than "+N events", so that I understand N means "additional events beyond those shown," not the day's total.
16. As a screen-reader user, I want the popover to be a properly labelled, non-modal dialog with predictable focus management (focus in on open, focus returned to the trigger on close), so that I can navigate the day's events and return to the surface.
17. As a screen-reader user, I want each list item to have a descriptive accessible name, so that I can identify events before activating them.
18. As a keyboard user, I want the "+N more" trigger to be a real focusable button I can activate with Enter/Space, so that I am not dependent on a mouse.
19. As a low-vision user, I want the popover to reuse the product's warm parchment/olive palette and the event's own color as the accent, so that it feels like part of the product.
20. As a connected user, I want the popover to position itself fully on screen (flipping above or clamping when near the viewport edge), so that it is never cropped off-screen.
21. As a connected user, I want opening the day list for a different Date Cell to switch the popover to that day, so that I can inspect several days in succession without extra dismiss steps.
22. As a user who disconnects while a Day Events Popover is open, I want the surface to behave sanely, so that the disconnected state is not broken — noting that until Saved Busy Blocks ship, the disconnected surface is empty.
23. As a future user of the disconnected surface (once Saved Busy Blocks exist), I want "+N more" to reveal the hidden Saved Busy Blocks for a day without titles, so that the overflow reveal works consistently across connected and disconnected states.
24. As a future disconnected user, I want list items to be non-interactive (no drill-through) because there are no titles or details to show, so that the privacy boundary of Saved Busy Blocks is preserved.
25. As a user, I want the Day Events Popover to never allow creating, editing, or deleting events, so that the surface's write-read-only identity is preserved.
26. As a connected user with many multiday events, I want a bar that spans several days to appear in each of those days' lists, so that each day list is a complete account of what is on that day.
27. As a connected user, I want the popover to render outside the virtualized scroll container (via a portal), so that scrolling or virtualization never unmounts or clips it incorrectly.
28. As a connected user, I want the visible cap in the Date Cell to stay at its current behavior, so that the cell layout I am used to does not change.
29. As a connected user with an extremely dense day, I want the popover's list to scroll internally rather than grow without bound, so that the popover never exceeds the viewport.
30. As a connected user, I want the Day Events Popover and the Event Detail Popover to share the same dismiss gestures, so that I only learn one set of interactions for "the thing floating over my calendar."

## Implementation Decisions

- **Event Layout Engine (modify existing deep module):** Today it returns, per cell, a capped `items` list (3 visible + an `overflow` count) and discards the rest. It is extended to additionally expose, per Date Cell, the **complete, ordered** set of Calendar Events attributed to that cell — Calendar Event Bars in lane order, then Calendar Event Rows by start time ascending. This full list is what the Day Events Popover renders. The capped `items` + overflow behavior for the cell itself is unchanged, so the visible cell layout and the 4-item cap are untouched. The module remains a pure function with no DOM dependencies, and the `overflow` count semantics (number of items hidden beyond the visible cap) are unchanged.

- **Day Events Popover controller (new state hook):** Owns the lifecycle of the Day Events Popover, mirroring the existing Event Detail Popover controller. Returns the currently selected Date Cell's day events (or null when closed), the anchor rect captured from the "+N more" trigger, a ref for outside-click detection, and `open(dayEvents, date, triggerEl)` / `close()` actions. Owns the dismiss wiring: close on surface scroll, close on outside click, close on Escape, and focus return to the trigger on close. It does **not** close on disconnect, because the popover is not connection-gated. Follows the existing single-cardinality controller pattern.

- **Day Events Popover (new presentational component):** Portaled to the document body (never a child of a virtualized Week Row), `role="dialog"` / `aria-modal="false"`, labelled by the date header. Renders a header with the cell's full date and a close button, then the full ordered list of events. Each Calendar Event Row item mirrors the cell (colored dot, start time, title); each Calendar Event Bar item shows its color and title with a secondary label from the existing `formatEventTiming` helper (e.g., "All day", or the date span). While the Google Account Connection is connected, each item is a button that summons the Event Detail Popover for that event; while disconnected, items are inert (no drill-through). Placement is `position: fixed`, computed via the existing pure placement module (reused unchanged), so it flips above / clamps to stay on screen. Reuses the product's parchment/olive palette with the event color as the accent.

- **Events Overflow trigger (modify existing cell rendering):** The overflow item in a Date Cell changes from a static line to a trigger. While connected it renders as a native `<button>` with a descriptive accessible name and `aria-expanded` reflecting popover state, labeled "+N more" (replacing "+N events"). While disconnected it remains a non-interactive indicator (until Saved Busy Blocks ship, the disconnected surface has no events anyway). Click / Enter / Space calls the day popover controller's `open`.

- **Mutual exclusivity (modify existing Calendar Surface):** The Calendar Surface becomes a thin orchestrator that composes the existing Event Detail Popover controller and the new Day Events Popover controller, and enforces "at most one overlay open": opening the Day Events Popover closes any open Event Detail Popover, and opening an Event Detail Popover (from a bar/row on the surface, or from an item inside the day list) closes the Day Events Popover. This realizes the single-cardinality rule across both overlays at the wiring level, without merging the two controllers.

- **Drill-through (compose existing):** Selecting an event in the Day Events Popover calls the existing Event Detail Popover controller's `open(event, triggerEl)` with the clicked list item as the trigger. Per mutual exclusivity, the Day Events Popover closes as the detail opens. This is available only while connected; disconnected list items have no drill-through.

- **Reuse of placement module (no change):** The pure popover-placement module is reused as-is by the Day Events Popover; no new geometry code is introduced.

- **Privacy (no change to the boundary):** The Day Events Popover introduces no new persisted data and no new network calls. It displays only what the Calendar Surface already holds in memory for that cell. The privacy boundary remains entirely on the connected-only Event Detail Popover. This extends ADR 0002's separate-layer pattern to a second sibling overlay and follows ADR 0004's reveal-not-disclose principle.

- **No shared-coordinator extraction yet:** The new controller intentionally duplicates the anchor/dismiss/focus logic of the Event Detail Popover controller rather than extracting a shared primitive. This matches the existing structure and avoids refactoring a working controller mid-feature. A shared "surface overlay coordinator" is noted as a future refactor should the duplication grow.

## Testing Decisions

- **What makes a good test here:** tests assert external behavior (given these events and this cell, the list contains these items in this order; given this user action, this overlay opens or closes), never implementation details (internal state shape, private helpers, effect ordering). The codebase's prior art follows this: pure modules are tested directly, and components and hooks are tested through their observable behavior.

- **Event Layout Engine (pure) — extend existing tests:** assert that the engine now exposes the complete ordered day-events per cell (bars by lane, then rows by start time), alongside the unchanged capped `items` + overflow. Cover: a cell with only rows, only bars, a mix, a bar spanning into the cell from a prior day, the ordering rules, and that the full list length equals `visible + overflow count`. Prior art: the existing layout test file.

- **Day Events Popover component (presentational) — new tests:** assert it renders the date header; renders every event for the day in the correct order; renders row items and bar items with their distinct appearance; invokes the drill-through callback when an item is activated while connected; and renders inert (non-interactive) items when disconnected. Prior art: the existing Event Detail Popover component test.

- **Calendar Surface integration — extend existing tests:** assert that clicking "+N more" opens the Day Events Popover for that cell; that opening it closes any open Event Detail Popover and vice versa (mutual exclusivity); that scroll, Escape, and outside-click dismiss it; and that selecting a list item opens the Event Detail Popover. Prior art: the existing Calendar Surface component test.

- **Controller hook — follow existing convention (no standalone test):** the existing Event Detail Popover controller has no standalone hook test; it is covered through its component and the surface integration test. The new controller follows the same convention and is covered the same way. This is a deliberate, confirmed choice to match the codebase's testing pattern.

- **Placement — no new tests:** the pure placement module is reused unchanged and remains covered by its existing tests.

## Out of Scope

- **Stacking the Day Events Popover behind the Event Detail Popover** (so closing detail returns to the list). Rejected for this slice in favor of single cardinality and the calm-overview identity; re-opening via "+N more" is the browse path. See ADR 0004.
- **Connection-gating the Day Events Popover.** Out of scope by design: it is a layout-overflow reveal with no privacy boundary of its own. See ADR 0004.
- **Rendering Saved Busy Blocks in the disconnected list.** The popover is designed to work for them, but Saved Busy Blocks themselves are not yet implemented (ADR 0001 is recorded but unbuilt). Until they ship, the disconnected surface is empty and the popover is only observable while connected.
- **Changing the visible cap or the overflow count semantics.** The 4-item cap and "+N = hidden count" are unchanged; this feature only makes the existing overflow trigger interactive.
- **Creating, editing, or deleting events.** The surface remains write-read-only permanently.
- **An agenda/timeline day view.** The Day Events Popover is a flat list mirroring the cell, not a chronological timeline.
- **Extracting a shared overlay coordinator.** Noted as a future refactor; not part of this PRD.

## Further Notes

- This PRD implements the design recorded in ADR 0004, which extends ADR 0002's separate-layer pattern to a second sibling overlay and establishes the reveal-not-disclose principle (the Day Events Popover has no privacy boundary of its own).
- Domain terms used here are defined in the [Web Experience](../../CONTEXT.md) and [Planning](../../../product/CONTEXT.md) contexts.
- The "+N more" relabel replaces the prior "+N events" copy; the overflow count semantics are unchanged.
- Forward-looking: when Saved Busy Blocks (ADR 0001) ship, the Day Events Popover will automatically reveal them (title-less, inert) with no architectural change — that is the payoff of the non-gating decision, and the moment to verify the disconnected list rendering feels right.
