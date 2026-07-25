# iOS Source Calendar selection specification

- **Status:** Accepted
- **Applies to:** Planner native iOS/iPadOS Google Calendar integration
- **Minimum deployment target:** iOS/iPadOS 17.0
- **Related:** [`calendar-surface.md`](calendar-surface.md), [`google-account-connection.md`](google-account-connection.md), [`../adr/0003-keep-calendar-events-memory-only.md`](../adr/0003-keep-calendar-events-memory-only.md), [`../adr/0006-persist-selected-source-calendars-per-account.md`](../adr/0006-persist-selected-source-calendars-per-account.md)

## Purpose and ownership

The iOS Experience lets a connected user choose the **Selected Source Calendars** whose **Calendar Events** appear on the **iOS Calendar Surface**. It uses Planning's shared domain semantics while presenting configuration through the native **iOS Source Calendar Control** and **iOS Source Calendar Picker**.

Planning owns Source Calendar, Primary Source Calendar, Selected Source Calendars, Source Calendar Reconciliation, Calendar Event, Event Color, Fetched Window, and Calendar Event Refresh semantics. The iOS Experience owns the controls, adaptive presentation, persistence boundary, status copy, and direct native Google Calendar integration. No executable code or persisted selection is shared with the Web Experience.

This capability remains behind the existing Google connection release gate. It introduces no additional authorization scope, backend, background processing, or Google Calendar write access.

**Implementation status:** disclosure version 3, complete initial Source Calendar loading, per-account restoration, pure reconciliation, the native user-driven multi-selection happy path, and live opening reload with failure recovery and revocation handling are delivered. The connected control indicates and disables only during the initial load and stays usable after a failure; opening the picker requests live Source Calendars — including as an automatic retry — with loading, Planner-owned error, and explicit Retry states that never discard the prior selection. Successful refreshes reconcile and persist immediately, the zero-source response persists the empty exception and clears Calendar data atomically, late results after dismissal are invalidated, and Disconnect on This Device closes the picker while retaining persisted toggles. A selected source's forbidden or not-found event failure triggers one live reload, reconciliation, and one aggregate retry, removing a selection only on confirmed unavailability. Cross-calendar occurrence deduplication and source detail, and bulk-selection/advanced accessibility behavior, remain follow-up slices.

## Accepted behavior

### Disclosure and connection gate

- Planner increments the Google connection disclosure version before enabling this capability. The revised explanation states that Planner reads events from the user's Selected Source Calendars, stores the selected Source Calendar IDs on this device, and stores no Calendar Events.
- An installation that acknowledged an older disclosure must acknowledge the revised explanation before Planner loads or persists multi-calendar configuration, including when an existing Google Account Connection restores after an app update. After restoration, Planner presents the revised explanation before any Source Calendar or Calendar Event request.
- Continuing records the new disclosure version and begins eager Source Calendar loading. Cancelling or dismissing the upgrade explanation preserves the Google Account Connection but performs no Calendar request or selection write, leaves the Calendar Grid event-empty, disables the iOS Source Calendar Control, and reports “Review Calendar access update to load events.” Planner offers the explanation again on the next foreground entry; Disconnect on This Device remains available.
- The iOS Source Calendar Control exists only while the release gate is on and the Google Account Connection is connected. It is usable only after current disclosure is acknowledged; restoration, expiration, or Disconnect on This Device never exposes a usable picker without both connection and acknowledgement.

### Available Source Calendars

- After disclosure acknowledgement and connection, Planner eagerly requests complete paginated Source Calendars from Google's technical `calendarList` resource directly through the SDK-managed access token.
- Available Source Calendars include every non-deleted, non-hidden entry whose Google access role permits reading event details. Free/busy-only entries are excluded.
- Each Source Calendar carries its stable Google ID, trimmed display summary, Google background color, and Primary Source Calendar marker. A missing or blank summary presents as “Untitled calendar”; Planner never presents a calendar ID as fallback text.
- A successful Source Calendars response is a prerequisite for Source Calendar Reconciliation and event fetching. If it fails, Planner preserves the persisted selection and any in-memory Calendar Events, performs no reconciliation or event refresh, reports the error without exposing Google's raw response, and offers Retry in the picker. A fresh process remains event-empty until Source Calendars load.
- Planner requests live Source Calendars whenever the picker opens, including as an automatic retry after an earlier failure. The picker indicates that attempt; if it fails, it retains the error and offers an explicit Retry without closing. Source Calendars created, deleted, hidden, or made unreadable since connection therefore appear through opening reconciliation without requiring reconnection.

### Selection and reconciliation

- A first selection contains only the Primary Source Calendar. If Google returns readable Source Calendars but no primary marker, the first deterministically ordered Source Calendar is the default.
- When at least one Source Calendar is available, Selected Source Calendars contains at least one entry. No arbitrary maximum applies. A successful response containing no available Source Calendars is the sole empty-selection exception: Planner persists an empty selection, clears Calendar Events, Fetched Window, and freshness atomically, and presents a distinct no-available-calendars error state without issuing an event request.
- Source Calendar Reconciliation runs after each successful Source Calendars load. It intersects stored IDs with the available Source Calendars, silently removes unavailable IDs, preserves all surviving IDs, and falls back to the default when none survive and a default exists. The reconciled result is persisted immediately.
- If an event request returns not-found or forbidden for one selected source, Planner reloads Source Calendars from Google's `calendarList` resource, reconciles against that live result, and retries the aggregate event request once. It removes a selection only when the response confirms that the source is unavailable; otherwise it retains the selection and reports refresh failure.

### Per-account persistence

- A dedicated store persists only Google's stable opaque account identifier and the Selected Source Calendar IDs in app-local `UserDefaults`. It persists no Source Calendar summary, color, Calendar Event, access token, email, or display name.
- Each account has an isolated selection. Toggles and reconciliation write the effective selection immediately.
- A selection survives process termination, ordinary restoration, and Disconnect on This Device so reconnecting the same account restores its configuration.
- Selections do not synchronize through a Planner backend, iCloud, the Web Experience, or another installation.
- The installation boundary clears every stored selection when it detects a fresh installation or migration to different hardware. The store does not use Keychain and therefore does not intentionally survive uninstall.

### iOS Source Calendar Control

- The connected-only control appears in the iOS Calendar Header immediately before the iOS Account Control. It uses a stable compact calendar glyph without a numeric badge so the existing geometric Visible Month remains centered at narrow widths.
- Its accessibility label includes the selected count, for example “Choose calendars, 3 selected.” It provides a 44-point activation target and the existing focus, pointer, hover, right-to-left, and accessibility behavior of header controls.
- During the initial Source Calendars request, the control is disabled and indicates progress. After that request fails it becomes usable again so the user can open the picker's error state and Retry.
- Opening the picker first dismisses an open Event Detail Popover. The two adaptive presentations are never stacked.

### iOS Source Calendar Picker

- The picker is an anchored popover in regular-width layouts and adapts to a sheet in compact-width layouts. It contains one scrollable native list and supports native outside-tap or interactive dismissal where the presentation permits.
- The Primary Source Calendar appears first. Remaining entries use one locale-independent order: Unicode-case-folded summary, then exact summary, then stable ID. This same order determines defaults, duplicate suffixes, and duplicate-event winners. Duplicate display summaries receive deterministic ordinal suffixes such as “Work” and “Work (2),” including in VoiceOver labels.
- Each row presents the Source Calendar's Google background color, display summary, selection checkmark, and a textual “Primary” marker where applicable. Selection is never communicated through color alone.
- Toggling a row changes and persists the selection immediately. The picker has no Save or Cancel action. It provides an explicit Done action, while every supported dismissal path has the same effect.
- Tapping the only selected row leaves it selected and presents “Select at least one calendar”; VoiceOver announces why the row was not deselected.
- A compact actions menu provides Select All and Reset to Primary. Reset uses the deterministic default if Google supplied no primary marker. The first release has no search.
- A Source Calendars loading failure presents an inline error and Retry without discarding the prior selection. If the picker closes before its opening Source Calendars refresh completes, Planner cancels or invalidates that request; its late result performs no reconciliation, persistence, or event refresh. Disconnect on This Device or confirmed connection expiration closes the picker immediately; toggles already committed remain persisted.

### Event fetching after selection

- Every initial load, expansion slab, and Calendar Event Refresh fetches Calendar Events from all Selected Source Calendars. The aggregate adapter hides Google URL construction, Source Calendar and event pagination, and event-color metadata lookup. It runs at most four per-Source-Calendar event requests concurrently; product behavior imposes no calendar-count limit.
- Event requests carry their Source Calendar identity and presentation attributes in memory. An event's Event Color remains its explicit Google event color when resolvable, otherwise its Source Calendar background color. Failure of account-wide optional event-color metadata alone degrades to Source Calendar colors and does not fail the aggregate request.
- Event content is all-or-nothing across the Selected Source Calendars. The complete paginated result for every selected source must succeed before the model commits any part of an initial load, slab, or refresh. A partial failure adds no freshness and leaves the prior atomic Calendar Events and Fetched Window unchanged.
- Routine event fetching pauses and coalesces while the picker is open. Closing without an effective selection change resumes with at most one pending routine request.
- Closing when the final effective selection differs from the opening selection, whether through user action or reconciliation, starts a user-visible “Updating events…” load. It preserves the Calendar Grid position and old event snapshot. In the active local Gregorian calendar, the request starts at local daybreak three calendar months before the earliest visible Date Cell and ends at local daybreak one day after the date three calendar months after the latest visible Date Cell; month arithmetic clamps to the destination month's last valid day, and both bounds clip to the Extended Calendar Range.
- A successful selection-triggered request atomically replaces the old Calendar Events, Fetched Window, and freshness coverage. Until success, the displayed snapshot retains the Source Calendar set used by its prior successful fetch and is explicitly stale under the updating or failure status; Planner never relabels those Calendar Events as results from the new selection. Failure retains those old values, keeps the newly persisted selection, and uses the existing refresh warning and retry behavior. Connectivity return or the next five-minute foreground interval retries it.
- Reopening and changing the picker while a selection-triggered request is in flight is allowed. Closing with a later effective selection cancels or invalidates the older request; stale completions never overwrite the latest selection.
- Routine refresh remains silent in flight. Selection-triggered loading is visible because the user is waiting for an intentional configuration change.

### Cross-calendar event identity

- The same event occurrence returned through multiple Selected Source Calendars presents once. Its cross-calendar identity is Google's `iCalUID` plus `originalStartTime` when supplied, otherwise that occurrence's all-day date or timed start. Distinct instances of a recurring event never collapse.
- If `iCalUID` is absent, identity falls back to Source Calendar ID plus Google's event ID; Planner does not guess that unrelated fallback events across calendars are duplicates.
- When duplicate copies disagree, the Primary Source Calendar copy wins when selected. Otherwise the copy earliest in the locale-independent Source Calendar order defined for the picker wins. Planner keeps the winning copy intact rather than combining title, color, link, or detail fields from different copies.
- Calendar Event Bars and Calendar Event Rows retain the winning source identity in memory. The Event Detail Popover presents a subdued row with that Source Calendar's color and summary, so source identity is available without relying on color alone.

### Status and accessibility

- Source Calendar loading and event failures use stable Planner-owned copy; raw Google errors, identifiers, and response bodies never reach the interface or logs.
- Connection errors retain their existing status priority. A Source Calendar loading failure prevents event loading; a selection-triggered event failure uses the existing atomic refresh warning.
- The picker supports VoiceOver, Switch Control, hardware keyboard navigation, Dynamic Type, right-to-left layout, and sufficient non-color selection semantics. Unlike fixed Calendar Event rows, picker text follows native accessibility sizing.

## Architecture boundaries

- A dedicated Source Calendars module owns the live available Source Calendars, per-account persisted IDs, Source Calendar Reconciliation, effective selection, picker lifecycle, and Source Calendar loading status. Its reconciliation core is pure and independently testable.
- `CalendarEventsModel` consumes resolved Selected Source Calendars and remains responsible for the atomic Calendar Event snapshot, Fetched Window, freshness, cadence, normalization, layout, and stale-completion protection. It does not own selection persistence or available Source Calendar presentation.
- The Google Calendar adapter exposes product-oriented Source Calendars and aggregate selected-source event operations. Callers do not construct one request per Source Calendar or coordinate partial results.
- The Google Account Connection exposes the connected account's stable opaque identifier only to the source-selection boundary. Email and other profile fields remain absent from persisted Planner state.

## Deterministic verification

Swift Testing uses a fake Source Calendar API, aggregate event adapter, account identity, persistence store, connectivity monitor, cadence clock, and fixed dates. Coverage includes:

- first-use Primary Source Calendar default, no-primary fallback, and the zero-calendar atomic clearing exception;
- pure reconciliation, removal of hidden/deleted/unreadable IDs, and persistence of the result;
- per-account isolation, relaunch and disconnect retention, and installation-boundary clearing;
- corrupt or missing stored values without crashes or cross-account leakage;
- full pagination and readable/non-hidden Source Calendar filtering;
- immediate toggles, minimum-one rejection, Select All, Reset to Primary, Done and interactive dismissal;
- Source Calendar loading, automatic opening retry, hard failure, explicit Retry, reopening refresh, dismissal-before-load-completion invalidation, and disconnect/expiration dismissal;
- no-Source-Calendar-count limit while never exceeding four concurrent per-Source-Calendar event requests;
- aggregate success, partial failure rollback, optional event-color degradation, forbidden/not-found reconciliation and one retry;
- visible-centered selection reload, old-snapshot retention, Header Status progress/failure, cadence retry, picker-open coalescing, and latest-selection-wins stale guards;
- occurrence-aware `iCalUID` deduplication, recurring-instance separation, fallback identity, deterministic winning copy, and source detail presentation;
- revised disclosure acknowledgement before Source Calendar loading or persistence, plus restored-account cancellation, event-empty suspension, foreground re-presentation, and Disconnect availability.

Deterministic SwiftUI previews cover compact sheet and regular popover forms, loading, list error with Retry, no available calendars, one and many calendars, duplicate/blank/long summaries, minimum-one explanation, right-to-left layout, large accessibility text, and VoiceOver labels.

## Manual acceptance matrix

Results requiring production-like OAuth configuration remain pending until performed honestly.

| Scenario | Environment | Expected result |
| --- | --- | --- |
| First connection | Real Google account with multiple calendars | Revised disclosure appears first; Primary Source Calendar is the sole default |
| Secondary and shared calendars | Real account with readable secondary/shared calendars | Every readable, non-hidden source appears and selected events load atomically |
| Hidden and free/busy-only calendars | Suitable Google account | Entries do not appear |
| Selection persistence | Relaunch, disconnect, and reconnect same account | Selection returns; Calendar Events refetch and remain memory-only |
| Account isolation | Two Google accounts connected sequentially | Each restores only its own selection |
| Installation boundary | Reinstall and migrated-device harness | Stored selections clear with local sign-in state |
| Adaptive picker | Compact iPhone and regular-width iPad | Sheet on iPhone, anchored popover on iPad, every dismissal applies identically |
| Many Source Calendars | Account with many Source Calendars | The picker remains responsive; Select All has no product cap; requests never exceed the concurrency bound |
| Partial event failure | Controlled proxy or deterministic adapter | Old atomic snapshot remains; warning appears; no partial freshness commits |
| Revoked Source Calendar | Remove access after selection | Source Calendar Reconciliation removes only a confirmed unavailable source and retries once |
| Duplicate invitation | Same occurrence visible through two sources | One event appears using the deterministic winning source |
| Accessibility | VoiceOver, keyboard, Switch Control, largest Dynamic Type, RTL | Rows, state, minimum-one reason, count, Done, and source detail are operable and announced |

## Out of scope

- Server, iCloud, web-to-iOS, or cross-installation selection synchronization
- Search within the picker
- Google Calendar writes, account switching, or more than one simultaneous Google Account Connection
- Persisting Source Calendar summaries/colors or any Calendar Event content
- Per-source partial event commits or per-source Fetched Window tracking
- Background refresh, push notifications, widgets, extensions, or live Source Calendar updates while the picker remains open
