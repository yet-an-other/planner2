# iOS Calendar Surface specification

- **Status:** Accepted
- **Applies to:** Planner 1.0 native iOS/iPadOS slice
- **Minimum deployment target:** iOS/iPadOS 17.0

## Purpose and ownership

The **iOS Calendar Surface** is the event-free native presentation of Planning's **Calendar Grid**. The **iOS Calendar Header** remains fixed above it. The iOS Experience owns this presentation while Planning owns the shared **Product Name**, **Today**, **Week Row**, **Date Cell**, **Extended Calendar Range**, **Month Marker**, **Visible Month**, and **Today Jump** language.

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
- Use a 64-point title row and 36-point weekday row beneath the top safe area.
- Place the Product Name on the leading side and the Visible Month at the geometric center.
- Derive Visible Month from the Monday of the topmost Week Row and update it while scrolling, not only after deceleration.
- Make Visible Month the only semantic product control. Activating it scrolls Today's Week Row to the top.
- Show its subtle warm capsule only while the control is pressed, focused, or hovered; keep no persistent border.
- Animate the Today Jump unless Reduce Motion is enabled. Do nothing when Today's Week Row is already topmost.

### Localization and direction

- Format Visible Month, weekday labels, day numerals, and Month Markers with the system locale while retaining Gregorian date arithmetic.
- Use localized short weekday labels in uppercase where casing applies.
- Keep semantic weekday and Date Cell order Monday through Sunday.
- Classify weekends with the locale's calendar rules rather than fixed Saturday/Sunday assumptions.
- Mirror the iOS Calendar Header and Calendar Grid for right-to-left languages. Monday remains at the leading edge, the Product Name moves to leading, and day numbers remain top-trailing.
- Keep long Visible Month labels on one line, scale them down modestly, then truncate without overlapping the Product Name or changing header height.

### Date Cell presentation

- An ordinary Date Cell contains only its compact localized day number, aligned top-trailing with monospaced system digits.
- Today uses a compact filled olive circle around the number. It has no whole-cell Today tint or textual label.
- Locale-defined weekend Date Cells and weekday labels use a subtle warm tint.
- The first Date Cell of each month adds an uppercase localized short Month Marker at the leading side of the same top row as the equally sized day number, plus a three-point olive rule on the cell's leading edge.
- Thin beige separators divide Date Cells and Week Rows. There is no outer card, shadow, rounded Calendar Grid container, or grid margin.
- Date Cells are inert: no selection, navigation, menu, gesture, haptic, or placeholder action.

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

## Interaction and product exclusions

Scrolling and Today Jump are the only product interactions. This slice contains no:

- Calendar Event type, event renderer, event placeholder, busy block, or overflow control
- Google Account Connection or Source Calendar
- Date selection, detail view, navigation route, tab, sheet, toolbar, menu, onboarding, or settings
- Persistence, restoration state, networking, permission, analytics, user notification, or extension
- Background-processing entitlement, continuously running timer, widget, or alternate scene
- Web font, third-party package, project generator, or executable dependency on `web/`

## Deterministic verification

The shared Planner scheme builds the application and runs Swift Testing against the observable `CalendarGridModel` seam. Tests use fixed instants, Gregorian calendars, locales, and timezones and cover:

- Today and Monday-through-Sunday Week Rows
- Extended Calendar Range boundaries and leap-day clamping
- Consecutive civil dates across daylight-saving changes
- Visible Month and Today Jump state
- Localized text, Monday-first semantics, weekend classification, and right-to-left direction
- Foreground, midnight, timezone, and locale refreshes
- Topmost Week Row preservation and both-boundary clamping

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
| Compact iPhone width | Deterministic 320-point Spanish preview | Pass: long Visible Month scales/truncates without collision |
| Compact iPad width | Deterministic 507-point Arabic preview | Preview pass: full-width RTL reflow without a sidebar or alternate layout; actual Split View runtime check remains pending |
| Native scrolling | iPhone 16 Pro, iOS 18.5 Simulator | Pass: native movement, transient indicator, immediate Visible Month; end-of-range boundary bounce was not separately re-run |
| Today Jump | iPhone 16 Pro plus deterministic model coverage | Pass: animated return and no-op state; manual Reduce Motion setting remains pending |
| Inert Date Cells | Simulator inspection and scope audit | Pass: no selection, navigation, menu, haptic, or gesture response |
| Foreground refresh | Deterministic model coverage and scene-adapter build | Automated pass: Today and browsing position refresh correctly; manual background/foreground run remains pending |
| Midnight refresh | Deterministic controlled-clock model coverage | Automated pass: Today moves without moving a browsing user; live controlled-clock run remains pending where practical |
| Locale and direction | Spanish and Arabic iPhone/iPad runs | Pass: localized labels/numerals, mirrored placement, locale weekend tint |
| App icon | iPhone home screen | Pass: opaque beige icon, unchanged centered glyph, system corner mask |

## Deferred validation and release work

The installed local runtimes include iOS 18.5 and iOS 26, but not iOS 17. Actual execution on an iOS 17 runtime remains a pre-release check even though generic-device compilation enforces the 17.0 deployment target.

Custom VoiceOver descriptions, accessibility-size layout tuning, formal contrast auditing, accessibility automation, and a complete accessibility acceptance pass are deferred. App Store metadata, signing administration, archives, notarization, TestFlight, distribution, and release automation are also outside this slice.
