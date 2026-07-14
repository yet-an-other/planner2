# PRD: Source Calendar Selection

## Problem Statement

The Calendar Surface currently fetches Calendar Events from the user's primary Google Calendar only. A user with more than one Google Calendar — a Work calendar, a Family calendar, a shared team calendar, a Holidays calendar — has no way to choose which calendars contribute events to the Calendar Surface. They cannot bring secondary or shared calendars onto the planning view, and they cannot suppress a calendar they do not want there. The product also has no settings surface of any kind today.

## Solution

Introduce the **Source Calendar** — a Google Calendar in the user's account that The Planner is permitted to fetch Calendar Events from — and let the user choose the **Selected Source Calendars**, the subset that contributes events to the Calendar Surface.

On connect, The Planner eagerly loads the user's calendar list and reconciles it against a per-device, per-account persisted selection (ADR 0003), defaulting to the primary calendar on first connect. A connected-only **Source Calendar Control** in the Calendar Header opens a modal **Source Calendar Picker** where the user toggles calendars (minimum one), with explicit Save / Cancel. Calendar Events are then fetched in parallel from every Selected Source Calendar, each colored by its own calendar, and merged with the existing id-based deduplication. A selection change resets and refetches the surface. Partial per-calendar failures degrade gracefully; total failures surface a hard error. This change preserves the Calendar Surface's calm, write-read-only identity (ADR 0002) and the memory-only-while-connected privacy boundary (ADR 0001).

## User Stories

1. As a connected user with multiple Google Calendars, I want to choose which of my calendars contribute events to the Calendar Surface, so that I see exactly the schedule I care about.
2. As a first-time connected user, I want my primary calendar to appear by default with no configuration, so that the Calendar Surface works exactly as it does today until I choose otherwise.
3. As a connected user, I want a control in the Calendar Header that opens the calendar chooser, so that I can find this setting next to the other account controls.
4. As a disconnected user, I do not want to see the calendar chooser, so that the header is not cluttered with a control I cannot use.
5. As a connected user opening the chooser, I want to see every readable, non-hidden calendar in my Google account, so that I can pick from my full set of calendars.
6. As a connected user, I want each calendar shown with its Google color and name, and the primary one marked, so that I can recognize them at a glance.
7. As a connected user, I want to toggle calendars on and off with checkboxes, so that selecting is quick and reversible before I commit.
8. As a connected user, I want a Select all action, so that I can bring in every calendar at once.
9. As a connected user, I want a Reset to primary action, so that I can quickly return to the default state.
10. As a connected user, I want to confirm my choice with a Save button and discard it with Cancel, so that my calendar only changes when I intend it to.
11. As a connected user, I want to be prevented from deselecting every calendar, so that I never end up with an empty, confusingly "connected but blank" surface.
12. As a connected user, I want the Save button to be disabled when my draft would select zero calendars, so that the minimum-one rule is enforced visibly.
13. As a user who has chosen my calendars, I want that choice remembered when I refresh the page or reconnect, so that I do not have to reconfigure every time.
14. As a user who uses The Planner on a second device, I accept reconfiguring there, so that the feature can work without a backend (ADR 0003).
15. As a user with calendars on two different Google accounts in the same browser, I want each account to remember its own selection, so that the accounts do not overwrite each other's choices.
16. As a connected user, I want events from all my selected calendars to appear together on the Calendar Surface, so that I see one unified planning view.
17. As a connected user, I want each event to use its own calendar's color by default, so that my color-coding stays meaningful across calendars.
18. As a connected user, I want an event I have explicitly color-coded in Google to keep that explicit color, so that my manual color choices win over the calendar default.
19. As a connected user, I want an event appearing in more than one selected calendar (e.g., a shared invitation) to show only once, so that I never see duplicates.
20. As a connected user, I want adding or removing a calendar to refresh the Calendar Surface to match, so that the view always reflects my current selection.
21. As a connected user, I want a brief loading indicator when the surface refreshes after a selection change, so that I know the new calendars are loading rather than missing.
22. As a connected user, I want one of my selected calendars failing to load not to blank out the whole surface, so that a single blocked or flaky calendar only affects itself.
23. As a connected user, I want to be told — without blocking — when some calendars could not load, so that I understand why part of my schedule is missing.
24. As a connected user, I want the total failure of all calendars, or of the calendar list itself, to surface a clear error, so that I know the surface genuinely could not load and can reconnect.
25. As a connected user, I want the chooser to reflect calendars I added or removed in another tab since I connected, so that newly created calendars are pickable without reconnecting.
26. As a connected user whose previously selected calendar was deleted or had its access revoked, I want it silently dropped from my selection, so that my selection stays valid automatically.
27. As a connected user whose entire stored selection no longer exists, I want to fall back to my primary calendar, so that the surface is never empty.
28. As a keyboard user, I want the chooser to be fully operable from the keyboard (open, toggle, Save, Cancel, close), so that I am not forced to use a mouse.
29. As a screen-reader user, I want the chooser's calendar list and each item's checked or unchecked state to be announced, so that I can make an informed selection.
30. As a user who disconnects while the chooser is open, I want it to close and discard my draft, so that I am never editing a selection I can no longer save.
31. As a user who disconnects, I want the Calendar Surface to fall back to Saved Busy Blocks as it does today, so that the multi-calendar change does not alter the offline or privacy behavior.
32. As a connected user scrolling through the Extended Calendar Range, I want slab fetching to fetch all selected calendars per slab, so that scrolling continues to fill in events from every selected calendar.
33. As a developer, I want the selection-reconciliation logic (intersect with available, fall back to primary, enforce minimum-one) to be a pure, tested function, so that edge cases are provable without a browser.

## Implementation Decisions

- **New deep module — Source Calendars.** Owns the available calendar list, the Selected Source Calendars, per-device persistence (ADR 0003), reconciliation against the live list, and the minimum-one invariant. It depends on the Google Account Connection for the access token but keeps auth concerns out of the connection module, which stays focused on the token and profile lifecycle. Its interface is a hook plus a pure core:
  - `useSourceCalendars(connection)` → `{ available: SourceCalendar[]; selection: SourceCalendarId[]; select(ids: SourceCalendarId[]): void; status: HeaderStatus | null }`. Loads the calendar list eagerly on connect, reconciles it against the persisted selection, and exposes the Picker's data and actions.
  - Pure core: `reconcileSelection(storedIds: SourceCalendarId[], available: SourceCalendar[]): SourceCalendarId[]` (intersect stored ids with available, drop gone or unreadable calendars, fall back to `[primary]` when the intersection is empty, enforce minimum-one), `loadPersistedSelection(accountEmail)`, and `persistSelection(accountEmail, ids)`.
  - Persistence is in `localStorage`, keyed per Google account (e.g. `planner.sourceCalendars.<email>`), storing a JSON array of stable Google calendar ids. This is the codebase's first persistence.
  - The decision-rich shape of a Source Calendar, which drives the Picker and the fetch:
    ```
    type SourceCalendar = { id: string; summary: string; backgroundColor: string; primary: boolean }
    ```

- **Modified deep module — Google Calendar Events.**
  - Add `fetchCalendarList(accessToken)` → `SourceCalendar[]`. This **replaces** today's separate primary-calendar lookup; the primary calendar's color now comes from the list.
  - Replace the single-calendar fetch with `fetchSourceCalendarEvents(accessToken, calendars: SourceCalendar[], range)` that fans out across the Selected Source Calendars in parallel and merges the results. Per-calendar color is baked into normalization: an event's color is its explicit Google event color when set, otherwise its own calendar's `backgroundColor`. The global Google colors call is unchanged.
  - The existing pure `normalizeGoogleCalendarEvents` core is reused; only its fallback-color input changes from a single primary color to the event's own calendar color. The `CalendarEvent` model is **not** extended with a Source Calendar id — color is baked at normalization, dedup is id-based, and keeping the model unchanged preserves the ADR 0001 privacy boundary (Saved Busy Blocks stay timing + color, no calendar identity).

- **Modified module — Calendar Events hook.** The Selected Source Calendars become a dependency of the connect effect, so any selection change triggers a full reset of the Fetched Window and a fresh ±6-month fetch for the new set (reusing the existing reset-on-disconnect path). Fetching uses an all-rejects-aware parallel strategy: if every calendar rejects, it is a hard error with Fetched Window rollback, exactly as today; if only some reject, the fulfilled calendars' events are merged and a non-fatal warning is surfaced; if all fulfill, status clears. A `calendarList` failure on connect is a hard error (no alias fallback); the persisted selection is left untouched and honored on the next successful connect.

- **Header Status widening.** The `HeaderStatus.tone` widens from `'info' | 'error'` to `'info' | 'warning' | 'error'`. `'warning'` is reserved for non-fatal partial per-calendar failures; `'error'` remains for total failures and the calendar-list failure.

- **Deduplication.** Reuses the existing id-based, first-wins merge unchanged. The same event appearing in two Selected Source Calendars (a shared invitation) collapses to a single Calendar Event.

- **New presentational component — Source Calendar Picker.** A modal dialog (backdrop, focus trap, explicit Save / Cancel) opened from the Source Calendar Control. Props: the available Source Calendars, the current selection, and `onSave` / `onCancel` callbacks. Each row shows a color swatch, the calendar summary, and a checkbox; the primary calendar is badged and listed first, the rest alphabetical. "Select all" and "Reset to primary" actions are provided, both obeying minimum-one. Save is disabled when the draft would leave zero calendars; on Save the draft is written to persistence and applied. A modal (rather than the non-modal Event Detail Popover pattern) is justified because choosing calendars is a deliberate configuration task, not a glance — distinct from the ADR 0002 reasoning that mandated a non-modal layer for event detail.

- **New presentational component — Source Calendar Control.** A Calendar Header button placed immediately left of the Account Control. It is hidden while the Google Account Connection is disconnected and disabled (with a spinner) while the calendar list is loading. Clicking it opens the Source Calendar Picker. Reopening the Picker refetches the calendar list so calendars added or removed in another tab become pickable.

- **Modified presentational component — Calendar Header.** Gains a slot for the Source Calendar Control, grouped with the Account Control on the right.

- **Disconnect while the Picker is open.** The modal closes immediately and the draft is discarded, mirroring ADR 0002's "popover closes if disconnected." The surface falls back to Saved Busy Blocks.

## Testing Decisions

A good test exercises external behavior, not implementation details: pure functions are tested directly with pinned inputs; presentational components are tested through the DOM via Testing Library; the hook is tested with a stubbed fetch and no network.

1. **Source Calendars pure core (highest value).** Cover `reconcileSelection` and the persistence round-trip: empty intersection falls back to `[primary]`; minimum-one is never violated; per-account keying isolates two accounts in one browser; deleted or unreadable stored ids are pruned; save then load round-trips. All pure, no DOM. Prior art: `fetched-window.test.ts`, `merge-calendar-events.test.ts`.
2. **Google Calendar Events normalization and fan-out.** Extend the existing suite: per-calendar color resolution (explicit event color beats calendar color), multi-calendar fan-out merges results, cross-calendar duplicates collapse by id, and a partial failure (one calendar rejects) still yields the other calendars' events. Prior art: `google-calendar-events.test.ts` and its event factory.
3. **Source Calendar Picker (component).** Render the list with swatches and the primary badge; toggling changes the draft; Save is disabled at one; Save applies the draft via `onSave`; Cancel discards via `onCancel`; "Select all" and "Reset to primary" obey minimum-one. Prior art: `event-detail-popover.test.tsx`, `calendar-surface.test.tsx`.
4. **Calendar Events hook (integration).** With a stubbed fetch: a selection change triggers a reset and refetch for the new set; a partial per-calendar failure sets a `'warning'` Header Status; a total failure sets an `'error'` and rolls the Fetched Window back. Prior art: `use-calendar-events.test.ts`.

Dedicated tests for the Source Calendar Control and the Calendar Header slot are intentionally skipped: they are trivial presentational wiring covered by the Picker test plus a smoke assertion.

## Out of Scope

- Server-side, per-account synchronization of the selection. The Planner has no backend; persistence is per-device (ADR 0003).
- Search or filtering within the Source Calendar Picker.
- Showing which Source Calendar a Calendar Event came from in the Event Detail Popover. This would require adding a Source Calendar id to the `CalendarEvent` model, reopening the ADR 0001 privacy boundary. Deferred.
- Per-calendar Fetched Window tracking for partial slab failures. The Fetched Window is treated as advanced unless a slab totally fails; a partially-failed calendar may have a gap until the next reconnect. This is a deliberate simplification.
- Any write access to Google Calendars. The Calendar Surface stays write-read-only (ADR 0002).
- Persisting anything beyond the selection. Saved Busy Blocks (ADR 0001) remain unimplemented; no events or busy blocks are persisted by this PRD.
- Live updates or push notifications for calendar changes; the list is refreshed only on connect and when the Picker is reopened.

## Further Notes

- This PRD introduces the codebase's first persistence. ADR 0003 records the per-device, per-account `localStorage` decision and notes that Saved Busy Blocks will likely follow the same mechanism.
- The eager `calendarList` call replaces today's separate primary-calendar lookup; the primary calendar's color is read from the list rather than from a dedicated call.
- Once selection is in play, events are fetched by explicit calendar id rather than the `primary` alias. The primary calendar remains the fallback selection when a stored selection cannot be reconciled against the live list.
- ADRs referenced: ADR 0001 (memory-only privacy boundary, preserved), ADR 0002 (calm overlay ethos — a modal is justified here as a deliberate config task rather than a glance), ADR 0003 (per-device persistence of the selection).
- Context terms added or updated this session: **Source Calendar**, **Selected Source Calendars**, and **Calendar Event** in [Planning](../../../product/CONTEXT.md); **Source Calendar Control** and **Source Calendar Picker** in the [Web Experience](../../CONTEXT.md).
