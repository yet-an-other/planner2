# iOS Calendar Surface specification

- **Status:** Accepted
- **Applies to:** Planner 1.0 native iOS/iPadOS slice
- **Minimum deployment target:** iOS/iPadOS 17.0
- **Related:** [`source-calendar-selection.md`](source-calendar-selection.md), [`google-account-connection.md`](google-account-connection.md)

## Purpose and ownership

The **iOS Calendar Surface** is the event-free native presentation of Planning's **Calendar Grid**. _Superseded for builds with the Google connection release gate enabled (development only): the enabled iOS Calendar Surface presents the user's Calendar Events as described in § Calendar Events (release gate) below. The gate stays off in all committed and production configurations, where the event-free presentation remains in force._ The **iOS Calendar Header** remains fixed above it. The iOS Experience owns this presentation while Planning owns the shared **Product Name**, **Today**, **Week Row**, **Date Cell**, **Extended Calendar Range**, **Month Marker**, **Visible Month**, and **Today Jump** language.

The iOS delivery stack is independent from the Web Experience. It shares vocabulary and behavior, not executable code, generated source, packages, or build commands.

## Accepted behavior

### Calendar Grid

- Use Gregorian civil dates in the active local timezone and force Monday-first semantics regardless of the user's preferred calendar.
- Generate complete Monday-through-Sunday Week Rows from the week containing ten years before Today through the week containing ten years after Today.
- Clamp February 29 to February 28 when a ten-year endpoint lands in a non-leap year.
- Keep every Week Row 96 points high with no gaps. Present seven equal-width Date Cells across the full available width.
- Preserve the topmost Week Row by date identity across rotation and window resizing rather than retaining a raw pixel offset.
- Scroll vertically with native momentum, bounce, and transient indicator behavior. Do not page, snap, or scroll horizontally.
- Open a fresh process with Today's Week Row at the top. Persist no restoration state.

### Header and Today Jump

- Keep the iOS Calendar Header fixed while Week Rows scroll below it.
- Use a 64-point title row and 36-point weekday row beneath the top safe area. _Superseded for builds with the Google connection release gate enabled (development only): the enabled iOS Calendar Header uses a 64-point title/control row with trailing iOS Source Calendar and Account Controls, a fixed 20-point iOS Header Status row, and the 36-point weekday row. The gate stays off in all committed and production configurations, where the dimensions and behavior here remain in force._
- Place the Product Name on the leading side and the Visible Month at the geometric center.
- Display the Product Version directly beneath the Product Name, sized like the iOS Header Status, in the palette's muted olive (the web Product Version's tone), trailing-aligned under the name and mirroring for right-to-left. Compose it from the bundle marketing version and build number as `v1.0.1`, prefixing `v` only when the marketing version starts with a digit; when the build number is absent, show the marketing version alone; when the marketing version is absent, omit the Product Version entirely.
- Derive Visible Month from the Monday of the topmost Week Row and update it while scrolling, not only after deceleration.
- Make Visible Month the only semantic product control. Activating it scrolls Today's Week Row to the top. _Superseded for builds with the Google connection release gate enabled (development only): the iOS Account Control and iOS Source Calendar Control are additional semantic product controls. The gate stays off in all committed and production configurations, where this statement remains in force._
- Show its subtle warm capsule only while the control is pressed, focused, or hovered; keep no persistent border.
- Animate the Today Jump unless Reduce Motion is enabled. Do nothing when Today's Week Row is already topmost.

### Localization and direction

- Format Visible Month, weekday labels, day numerals, and Month Markers with the system locale while retaining Gregorian date arithmetic.
- Use localized short weekday labels in uppercase where casing applies.
- Keep semantic weekday and Date Cell order Monday through Sunday.
- Classify weekends with the locale's calendar rules rather than fixed Saturday/Sunday assumptions.
- Mirror the iOS Calendar Header and Calendar Grid for right-to-left languages. Monday remains at the leading edge, the Product Name moves to leading, and day numbers remain top-trailing.
- Present the Visible Month as the localized short month-and-year form (for example, Jan 2026) on one line; scale it down modestly, then truncate, without overlapping the Product Name or changing header height.

### Date Cell presentation

- An ordinary Date Cell contains only its compact localized day number, aligned top-trailing with monospaced system digits. _Superseded for builds with the Google connection release gate enabled (development only): an ordinary Date Cell additionally presents its Calendar Event Bars, Calendar Event Rows, and Events Overflow marker below the day number as described in § Calendar Events (release gate). The gate stays off in all committed and production configurations, where this statement remains in force._
- Today uses a compact filled olive circle around the number. It has no whole-cell Today tint or textual label.
- Locale-defined weekend Date Cells and weekday labels use a subtle warm tint.
- The first Date Cell of each month adds an uppercase localized short Month Marker at the leading side of the same top row as the equally sized day number, plus a three-point olive rule on the cell's leading edge.
- Thin beige separators divide Date Cells and Week Rows. There is no outer card, shadow, rounded Calendar Grid container, or grid margin.
- Date Cells are inert: no selection, navigation, menu, gesture, haptic, or placeholder action. _Superseded for builds with the Google connection release gate enabled (development only): Calendar Event Bars and Rows summon the read-only Event Detail Popover (§ Event Detail Popover below) and the Events Overflow marker summons the read-only Day Events Popover (§ Day Events Popover below); Date Cells are otherwise inert. The gate keeps the statement here in force in committed and production builds._

### Live system changes

- Recompute Today, localized text, Today Jump, and the Extended Calendar Range on foreground entry and relevant clock, timezone, and locale changes.
- While active, keep one cancellable sleep scheduled for the next DST-safe local midnight. Cancel it outside the active scene and reschedule after system changes.
- Preserve the same topmost civil Week Row when it remains in the refreshed range. Clamp an out-of-range position to the nearest new boundary.
- Never move a browsing user to Today merely because Today changed.

### Visual and application identity

- Use the fixed warm beige/olive light palette, readable dark foregrounds, and native system typography.
- Deliberately remain light when the system uses Dark appearance.
- Launch on a static opaque `#F5F1E6` background with no title, glyph, animation, loading state, or progress.
- Use the unchanged web calendar glyph, centered on an opaque `#F5F1E6` app-icon background. Let the operating system apply the corner mask.

## Calendar Events (release gate)

_Development-only: every statement in this section applies only to builds with the Google connection release gate enabled. The gate stays off in all committed and production configurations, where none of this behavior exists._

### Sources and fetching

- While the Google Account Connection is connected, the iOS Calendar Surface presents Calendar Events from the Selected Source Calendars according to [`source-calendar-selection.md`](source-calendar-selection.md). The Primary Source Calendar remains the first-use default.
- Calendar Events are fetched directly from the Google Calendar API with the SDK-managed access token (ADR 0001); Planner's backend is never involved.
- The initial Fetched Window covers Today ± 3 months. When the visible range comes within one month of a Fetched Window edge, a two-month slab fetch extends the window in that direction. Each expansion slab is fetched once per process run unless it fails; a failed slab leaves its range empty and retries on the next approach.
- Every successful initial, slab, and Calendar Event Refresh request records memory-only freshness for its completed range at its completion time. While connected and foreground-active, scrolling to a visible-plus-one-month-buffer range that is not fully covered by successes from the preceding five minutes requests an immediate Calendar Event Refresh, clipped to the Fetched Window. Recent initial, slab, and refresh ranges can jointly provide coverage; a gap makes the range stale. Still-fresh ranges suppress duplicate browsing requests. A failed or obsolete request adds no freshness, Disconnect on This Device clears all coverage, and no freshness metadata is persisted.
- Recurring events arrive expanded into per-date instances; cancelled events and events the user declined are hidden.
- When connected Planner returns to the foreground after the initial Fetched Window has loaded, it performs a Calendar Event Refresh for the visible dates and a one-month scroll-prefetch buffer on each side, clipped to the Fetched Window. While the scene remains foreground-active, it repeats Calendar Event Refresh five minutes after the preceding initial, slab, or refresh request attempt completes; completion-relative cadence prevents slow requests from accumulating overlapping work. Leaving the active scene cancels the pending interval, and returning requests the immediate foreground refresh before beginning a new interval after that work completes. The complete paginated aggregate result from every Selected Source Calendar atomically replaces intersecting Calendar Events, including additions, edits, moves, declines, and deletions, while preserving Calendar Events outside the refreshed range; failure from any selected source commits none of the aggregate. Initial, slab, and refresh requests serialize; foreground, connectivity, scrolling, and cadence triggers coalesce against current state and the latest visible range. Required two-month slab expansion runs before any bounded browsing refresh and remains the only operation that grows the Fetched Window. Existing events remain visible and routine refresh stays silent while in flight. A failed refresh retains them with a warning and retries on connectivity return or the next active interval; a later success clears that warning. An open Event Detail Popover follows the selected canonical Calendar Event identity through successful replacement: edits and moves within the refreshed range update it in place, while deletion, decline, or movement outside the refreshed canonical range dismisses it; failure leaves it unchanged. Disconnect on This Device and model teardown cancel cadence. Calendar Event Refresh never expands the Fetched Window. No cadence exists while inactive, disconnected, or release-gated off, and no background processing is introduced.

### Presentation

- An all-day event of any length and a timed event spanning multiple local days present as a Calendar Event Bar in its Event Color — its explicit Google event color when one is set, otherwise the Source Calendar's background color — with contrast-safe text, lane-ordered by start date, then start time, then longer duration first. The title begins in the leading-edge Date Cell and continues across subsequent cells, mirrored for right-to-left; a bar crossing a Week Row boundary splits into truncated segments with square continuing edges.
- A timed single-day event presents as a Calendar Event Row — a dot in its Event Color, a localized start time, and a title — ordered by start time within its Date Cell. In a Month Marker cell, rows receive two extra points of leading clearance from the thick month rule, mirrored for right-to-left.
- Explicit Google event colors resolve through Google's colors metadata, fetched alongside event fetches; when it is unavailable, affected events silently use the Source Calendar's background color and the iOS Header Status says nothing. Bar titles use whichever of Planner's ink or white has the stronger APCA lightness contrast against the Event Color (ADR 0004).
- A Date Cell presents at most four event slots at the fixed 96-point Week Row height; beyond the cap it shows three items plus the Events Overflow marker carrying the hidden count, in bars-then-rows order. A bar lane deeper than the third renders only when every Date Cell it crosses fits at true lane positions with no rows and no overflow beneath it; otherwise it counts into the overflow of every cell it crosses. Rows and the marker never paint past the fixed Week Row.
- Calendar Event Bars and Calendar Event Rows render 14 points tall with 10-point text and do not scale with Dynamic Type.
- The Events Overflow marker is inert: it reads the hidden count and summons nothing. _Superseded for builds with the Google connection release gate enabled (development only): the Events Overflow marker summons the read-only Day Events Popover (§ Day Events Popover below). The gate keeps the inert marker in force in committed and production builds._ Date Cells are otherwise inert — beyond Calendar Event Bars and Rows summoning the Event Detail Popover (§ Event Detail Popover below) and the Events Overflow marker summoning the Day Events Popover, scrolling and Today Jump remain the only product interactions.
- A missing or blank event summary presents as “Busy”.

### Event Detail Popover

- Tapping a Calendar Event Bar — any segment of a multiday bar — or a Calendar Event Row summons the Event Detail Popover (Planning glossary; ADR 0005): a native anchored popover adapting on compact widths to a full-width, canvas-colored sheet that opens at half height and can expand to full height, with a small close affordance. It dismisses by outside tap, the affordance, or the platform gesture — never by surface scroll.
- The popover presents the event's title with an Event Color accent and a localized timing line: “All day · date” for a single all-day event, “All day · start – end” for a multiday one, and “date · start – end” for a timed one, with a timed multiday event carrying date and time on both ends.
- The popover presents the winning Source Calendar's color and summary in a subdued row, never relying on color alone to communicate source identity.
- A Where section presents the event's location when Google provides one: a place string renders as text with a Google Maps search link on its pin affordance, and a location that is itself an http(s) URL renders as a direct link. The location stays a plain string in the data model; linkification is presentation-only.
- A Notes section presents the event's notes as plain text — HTML stripped at normalization, authored line breaks preserved, Google's auto-created-event boilerplate removed — with http(s) URLs tappable; long notes scroll within the section. The notes stay plain text in the data model; linkification is presentation-only.
- An Attendees section presents the event's attendees when it has them: display name when present, email otherwise, each with the response status as text — accepted, declined, tentative, invited, or unknown, never color alone — capped at five with a “+N more” line for the rest.
- An “Open in Google Calendar →” footer links to the event in Google Calendar when Google provides the link. Sections and the footer are omitted when their data is absent, so a sparse event stays clean.
- Calendar Event Bars and Rows carry the canonical identity and winning Source Calendar identity defined by the selection specification. Opening the popover records that identity in the observable Calendar Events model and projects detail from its canonical normalized Calendar Event. Successful Calendar Event Refresh therefore updates every presented field in place while that identity remains canonical, including after a move within the refreshed range; deletion, decline, movement outside the refreshed canonical range, and Disconnect on This Device dismiss the popover as consequences of canonical Calendar Events clearing. Failed refresh leaves the existing selection and detail unchanged (ADR 0005).
- The popover is the surface's single read-only exception: it carries no edit affordances, the Events Overflow marker stays inert, and Date Cells are otherwise inert. _Superseded for builds with the Google connection release gate enabled (development only): the Event Detail Popover and the Day Events Popover are the surface's read-only exceptions, neither carries edit affordances, and the Events Overflow marker summons the Day Events Popover (§ Day Events Popover below). The gate keeps the inert marker in force in committed and production builds._

### Day Events Popover

- Tapping the Events Overflow marker in a Date Cell summons the Day Events Popover (Planning glossary): a native anchored popover, anchored to the marker, adapting on compact widths to a sheet that opens at half height and can expand to full height, with a small close affordance. It dismisses by outside tap, the affordance, or the platform gesture.
- The popover lists every Calendar Event attributed to the Date Cell — visible and hidden alike, including multiday and all-day Calendar Event Bars crossing the day — in the cell's own ordering: Calendar Event Bars in lane order, then Calendar Event Rows by start time ascending. A bar crossing several days appears in each such day's list.
- Items render with the cell's own visual language — Calendar Event Bars as colored bars with contrast-safe titles, Calendar Event Rows with an Event Color dot, localized start time, and title — under a localized date heading naming the Date Cell (for example, "Monday, June 9"). Dense days scroll within the popover.
- The list opens from memory-only Calendar Events with no network call, and it is read-only: the visible cap and the "+N = hidden count" semantics are unchanged, and the popover creates, edits, and deletes nothing.

### Availability and status

- Calendar Events are memory-only (ADR 0003): they are never persisted, they vanish on Disconnect on This Device, and they refetch per process run. There are no offline placeholders. Every detail the Event Detail Popover presents shares this boundary.
- The iOS Header Status presents fetch progress, fetch and refresh failures, and offline conditions in Planner-owned copy; raw Google errors never reach it. Connection warnings and errors lead; event-fetch progress and issues override resting connection information. Routine Calendar Event Refresh presents no progress message.
- An offline initial fetch leaves the bare, usable Calendar Grid with a warning and retries event-driven on connectivity return; an initial fetch that fails for any other reason reports an error. A failed slab keeps already-fetched events visible with a fetch-issue message and recovers on connectivity return or the next edge approach.

## Interaction and product exclusions

Scrolling and Today Jump are the only product interactions. _Superseded for builds with the Google connection release gate enabled (development only): Connect, Disconnect on This Device, the first-connect explanation actions, Source Calendar selection, and summoning the read-only Event Detail Popover and Day Events Popover are additional product interactions; the gate keeps them inactive in committed and production builds._ This slice contains no:

- Calendar Event type, event renderer, event placeholder, busy block, or overflow control. _Superseded for builds with the Google connection release gate enabled (development only): enabled builds present Calendar Events per § Calendar Events (release gate); the Events Overflow marker is a control summoning the Day Events Popover, and no busy block exists. The gate keeps them inactive in committed and production builds._
- Google Account Connection or Source Calendar. _Superseded only for development builds with the Google connection release gate enabled, which present the gated connection behavior plus Source Calendar selection according to the related specifications._
- Date selection, detail view, navigation route, tab, sheet, toolbar, menu, onboarding, or settings. _Superseded only for the gated first-connect explanation, Event Detail Popover, Day Events Popover, and iOS Source Calendar Picker with its compact actions menu; every other listed exclusion remains in force._
- Persistence, restoration state, networking, permission, analytics, user notification, or extension. _Superseded only as needed by the gated Google Account Connection, Selected Source Calendars, and Calendar Events: enabled builds persist disclosure and installation markers plus account-keyed Selected Source Calendar IDs (ADR 0006), reach Google for authorization, profile presentation, Source Calendars, and Calendar Events, request Calendar read authorization, and keep Calendar Events memory-only; no other persistence, networking, permission, analytics, notification, or extension exists, and the gate keeps the additions inactive in committed and production builds._
- Background-processing entitlement, continuously running timer, widget, or alternate scene
- Web font, project generator, or executable dependency on `web/`
- Third-party packages, with one reviewed exception: the pinned Google Sign-In for iOS SDK behind the build-time Google connection release gate. _Superseded only as recorded in the native-authentication ADR; the gate keeps the addition inactive in committed and production builds._

## Deterministic verification

The shared Planner scheme builds the application and runs Swift Testing against the observable `CalendarGridModel` seam. Tests use fixed instants, Gregorian calendars, locales, and timezones and cover:

- Today and Monday-through-Sunday Week Rows
- Extended Calendar Range boundaries and leap-day clamping
- Consecutive civil dates across daylight-saving changes
- Visible Month and Today Jump state
- Localized text, Monday-first semantics, weekend classification, and right-to-left direction
- Foreground, midnight, timezone, and locale refreshes
- Topmost Week Row preservation and both-boundary clamping

The gated Calendar Events are covered through the observable Calendar Events model seam with a fake Google Calendar API adapter, a fake connectivity monitor, a controllable cadence scheduling clock, and fixed instants, Gregorian calendars, locales, and timezones: Fetched Window expansion and once-per-range fetching, normalization and classification, lane ordering and the visible cap with Events Overflow counts, Header Status messaging and resolution between the two publishers, offline recovery, serialized initial/slab/refresh requests, bounded foreground Calendar Event Refresh and atomic replacement, five-minute completion-relative active cadence, initial/slab/refresh freshness coverage, browsing suppression and immediate stale-range refresh, partial coverage, failure retry, inactive and disconnect cancellation, trigger coalescing against the latest visible range, teardown, refresh warning recovery, and stale-completion guarding. Tests advance freshness time and fire scheduled actions directly and never wait five real minutes. The Event Detail Popover is covered through the same seam: canonical identity selection; in-place title, timing, Event Color, location, notes, attendee, and Google-link replacement across an edit or move; disappearance after deletion or decline; failure retention; disconnect clearing; timing lines for every event shape under fixed locale and timezone; and plain-text line-break preservation. Its compact-width and detent policy is pinned directly. The Day Events Popover is covered through the same seam: summoning a Date Cell's complete ordered day — Calendar Event Bars in lane order, including cap-hidden lanes and multiday bars crossing the day, then Calendar Event Rows by start time ascending — with no network call, dismissal, and Disconnect on This Device clearing; its compact-width and detent policy is pinned directly, and its deterministic previews cover a dense day, compact and wide widths, and right-to-left layout. Deterministic SwiftUI previews cover bars spanning Date Cells, rows, Month Marker cells, dense days, compact and wide widths, and right-to-left layouts. The popover previews cover compact, regular, and right-to-left layouts; the compact and regular reconciliation harnesses exercise open presentation across edit, move, deletion, decline, failure, and disconnect outcomes.

See [`../../README.md`](../../README.md) for copyable build and test commands. CI runs only for this delivery stack and shared Planning/context changes; it performs no signing, archive, App Store, TestFlight, or deployment work.

## Manual acceptance matrix

| Scenario | Environment | Result |
| --- | --- | --- |
| Small iPhone portrait | iPhone SE (3rd generation), iOS 18.5 Simulator | Pass: fixed header, equal columns, Today, Month Marker, no blanking |
| Small iPhone landscape | iPhone SE (3rd generation), iOS 18.5 Simulator | Pass: seven reflowed columns, fixed-height Week Rows, no alternate layout |
| Large iPhone portrait | iPhone 16 Pro Max, iOS 18.5 Simulator | Pass: full-width Calendar Grid and complete light presentation |
| Large iPhone with system Dark | iPhone 16 Pro Max, iOS 18.5 Simulator | Pass: application remains in the designed light appearance |
| iPad portrait | 11-inch iPad Pro, iOS 18.5 Simulator | Pass: full-width Calendar Grid, RTL presentation, no card or maximum width |
| iPad landscape | 11-inch iPad Pro, iOS 18.5 Simulator | Pass: position identity retained and seven columns reflowed without blanking |
| Compact iPhone width | Deterministic 320-point Spanish preview | Pass: Visible Month short form scales/truncates without collision |
| Compact iPad width | Deterministic 507-point Arabic preview | Preview pass: full-width RTL reflow without a sidebar or alternate layout; actual Split View runtime check remains pending |
| Native scrolling | iPhone 16 Pro, iOS 18.5 Simulator | Pass: native movement, transient indicator, immediate Visible Month; end-of-range boundary bounce was not separately re-run |
| Today Jump | iPhone 16 Pro plus deterministic model coverage | Pass: animated return and no-op state; manual Reduce Motion setting remains pending |
| Inert Date Cells | Simulator inspection and scope audit | Pass: no selection, navigation, menu, haptic, or gesture response; gate-on builds except bars and rows summoning the Event Detail Popover (see the popover row) |
| Foreground refresh | Deterministic grid and Calendar Events model coverage plus scene-adapter build | Automated pass: Today and browsing position refresh correctly; connected gate-on builds request a bounded, silent Calendar Event Refresh with atomic replacement and failure retention; manual background/foreground run remains pending |
| Five-minute foreground cadence | Controllable scheduling-clock coverage plus connected gate-on simulator | Automated pass: cadence starts after request completion, pauses inactive, resumes through immediate foreground refresh, retries failure, and cancels on disconnect/teardown without real-time waits; manual five-minute foreground/inactive observation remains pending |
| Stale-range refresh while browsing | Controllable scheduling-clock and Calendar Events model coverage | Automated pass: initial, slab, and refresh successes jointly suppress duplicate requests for five minutes; scrolling into partial or expired coverage runs required slab expansion first, keeps existing events visible, then refreshes the latest bounded range; manual long-session browsing observation remains pending |
| Midnight refresh | Deterministic controlled-clock model coverage | Automated pass: Today moves without moving a browsing user; live controlled-clock run remains pending where practical |
| Locale and direction | Spanish and Arabic iPhone/iPad runs | Pass: localized labels/numerals, mirrored placement, locale weekend tint |
| Product Version | iPhone SE (3rd generation), iOS 18.5 Simulator, English and Arabic runs | Pass: `v1.0.1` beneath the Product Name, trailing-aligned and mirrored, header height unchanged |
| App icon | iPhone home screen | Pass: opaque beige icon, unchanged centered glyph, system corner mask |
| Calendar Events presentation | Deterministic SwiftUI previews (gate on) | Preview compile pass: bars spanning cells, dotted rows, dense day with Events Overflow, Month Marker cell, compact/wide/RTL layouts; visual inspection run pending |
| Day Events Popover | Deterministic SwiftUI previews plus observable Calendar Events model coverage (gate on) | Automated pass: summoning lists the Date Cell's complete ordered day — visible and cap-hidden items alike, bars in lane order including multiday crossings, then rows by start time — from memory with no network call, clearing on dismissal and Disconnect on This Device; compact/wide/RTL preview compile pass in place, while tap, dismissal, and sheet-adaptation runs remain pending |
| Event Detail Popover | Deterministic SwiftUI previews plus observable Calendar Events model coverage (gate on) | Automated pass: canonical identity selection updates every detail field across edit and move, dismisses on deletion, decline, movement outside the refreshed range, and Disconnect on This Device, and retains detail on refresh failure; compact/wide/RTL preview compile pass remains in place, while tap, dismissal, and sheet-adaptation runs remain pending |
| Real-OAuth event fetching and offline recovery | Production-like OAuth configuration | Pending — external OAuth configuration required |

## Deferred validation and release work

The installed local runtimes include iOS 18.5 and iOS 26, but not iOS 17. Actual execution on an iOS 17 runtime remains a pre-release check even though generic-device compilation enforces the 17.0 deployment target.

Custom VoiceOver descriptions, accessibility-size layout tuning, formal contrast auditing, accessibility automation, and a complete accessibility acceptance pass are deferred. App Store metadata, signing administration, archives, notarization, TestFlight, distribution, and release automation are also outside this slice.
