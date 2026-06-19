# Planner

Planner is a personal planning product whose first slice is a calendar-only surface.

## Language

**Fetched Window**:
The continuous date range from the earliest to the latest date that has been fetched from Google Calendar. Represented as two boundary dates (`earliestFetched` and `latestFetched`). The Fetched Window is extended one slab at a time when scrolling past either edge.
_Avoid_: fetched cache, loaded range, data window

**Calendar Surface**:
A Monday-first, bidirectionally scrollable seven-column calendar grid that presents dates in an Extended Calendar Range and overlays the user's Calendar Events for planning.
_Avoid_: Planner app, full planner, schedule manager, infinite calendar

**Calendar Header**:
The non-scrolling area that displays the Product Name, Visible Month, and Monday-first weekday labels for the Calendar Surface.
_Avoid_: Top bar, sticky header, current month header

**Product Name**:
The public name of the product: The Planner.
_Avoid_: App name, site title, brand label

**Product Version**:
The public version identifier displayed with the Product Name.
_Avoid_: Build number, package version, release tag

**Google Account Connection**:
The user's authorization for The Planner to identify them with Google and read their Google Calendar.
_Avoid_: Login, Google auth, OAuth token

**Account Control**:
The Calendar Header control that displays the Google Account Connection state and lets the user connect or manage the connected account.
_Avoid_: Login button, profile button, auth widget

**Header Status**:
A Calendar Header area for short connection information, progress messages, or errors related to the Calendar Surface.
_Avoid_: Toast, alert, notification bar

**Visible Month**:
The month and year containing the first date in the topmost visible Week Row of the Calendar Surface.
_Avoid_: Current month, active month, shown month

**Week Row**:
A Monday-through-Sunday row of seven consecutive Date Cells in the Calendar Surface.
_Avoid_: Date row, calendar row

**Date Cell**:
A single date in the Calendar Surface.
_Avoid_: Day card, calendar tile, date box

**Month Marker**:
The first Date Cell of a calendar month, labeled with that month's short name.
_Avoid_: Month divider, month label, month start

**Today**:
The current calendar date in the viewer's local timezone.
_Avoid_: Current day, system date, UTC date

**Today Jump**:
A Calendar Header action that returns the Calendar Surface to Today's Week Row.
_Avoid_: Back to today, scroll home, month click

**Calendar Event**:
A Google Calendar event fetched from the primary calendar and rendered on the Calendar Surface while the Google Account Connection is active.
_Avoid_: Event item, schedule entry, appointment

**Calendar Event Bar**:
A visual representation of a multiday or all-day Calendar Event rendered as a solid colored bar spanning one or more Date Cells.
_Avoid_: Event strip, block, banner

**Calendar Event Row**:
A visual representation of an intraday Calendar Event rendered inside a single Date Cell with a dot, start time, and title.
_Avoid_: Event chip, pill, card

**Saved Busy Block**:
A privacy-preserving placeholder persisted for offline use that retains a Calendar Event's timing and color but not its title.
_Avoid_: Cached event, local event, offline event

**Extended Calendar Range**:
The complete Monday-through-Sunday Week Rows from the week containing ten years before Today through the week containing ten years after Today.
_Avoid_: Infinite range, endless dates, all dates

## Relationships

- A **Calendar Header** belongs to exactly one **Calendar Surface**.
- A **Calendar Header** displays one **Product Name**.
- A **Calendar Header** displays one **Product Version**.
- A **Calendar Header** displays one **Visible Month**.
- A **Calendar Header** contains one **Account Control**.
- A **Calendar Header** contains one **Header Status**.
- An **Account Control** displays the **Google Account Connection** state.
- A **Google Account Connection** is either connected or disconnected.
- A **Calendar Surface** presents the **Extended Calendar Range**.
- A **Calendar Surface** contains **Week Rows** ordered by date.
- A **Week Row** contains exactly seven **Date Cells**.
- A **Calendar Surface** displays **Calendar Events** when the **Google Account Connection** is connected.
- A **Calendar Surface** displays **Saved Busy Blocks** when the **Google Account Connection** is disconnected.
- A **Visible Month** is derived from exactly one topmost visible **Week Row** in the **Calendar Surface**.
- A **Calendar Surface** contains one **Date Cell** for each consecutive date it presents.
- Each calendar month in the **Calendar Surface** has exactly one **Month Marker**.
- **Today** belongs to exactly one **Date Cell** in the **Calendar Surface**.
- A **Today Jump** targets the **Week Row** containing **Today**.
- A **Calendar Event** is either a **Calendar Event Bar** or a **Calendar Event Row**.
- A **Calendar Event Bar** spans one or more **Date Cells**.
- A **Calendar Event Bar** shows its title starting in the leftmost **Date Cell** and continuing across subsequent **Date Cells**.
- A **Calendar Event Bar** belongs to a vertical lane within each **Date Cell** it spans; bars are globally ordered by start date then start time then duration (longer first), and rows by start time.
- A **Calendar Event Row** belongs to exactly one **Date Cell**.
- A **Fetched Window** belongs to a connected **Google Account Connection** and is expanded by scroll-driven slab fetches.

## Example dialogue

> **Dev:** "Should the first version of the planner include tasks or events?"
> **Domain expert:** "No — the first version is only the **Calendar Surface**, anchored on **Today** in the viewer's local timezone."
>
> **Dev:** "What happens to Calendar Events when the user disconnects their Google Account Connection?"
> **Domain expert:** "The Calendar Surface falls back to **Saved Busy Blocks** — placeholders that keep the shape of the calendar without exposing the original event titles."

## Flagged ambiguities

- "planner app" could mean a full planning product with events, tasks, and reminders; resolved: this first slice is the **Calendar Surface** only.
- "infinite scroll" could mean literally unbounded dates; resolved: the Calendar Surface uses an **Extended Calendar Range**.
- "event-free" was the original definition of the Calendar Surface; resolved: the Calendar Surface now displays **Calendar Events** while connected and **Saved Busy Blocks** while disconnected.
- "all-day" vs "multiday" in Google Calendar: an all-day event spanning multiple days is visually treated the same as a multiday timed event and rendered as a single **Calendar Event Bar** spanning all affected **Date Cells**.
