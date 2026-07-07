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

**Source Calendar Control**:
The connected-only Calendar Header control that opens the Source Calendar Picker so the user can change the Selected Source Calendars.
_Avoid_: Settings button, calendar filter, gear, preferences

**Source Calendar Picker**:
A modal dialog, opened from the Source Calendar Control, that lists the user's Source Calendars and lets the user change the Selected Source Calendars (minimum one) with explicit Save / Cancel.
_Avoid_: Settings modal, calendar dialog, preferences screen

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

**Source Calendar**:
A Google Calendar in the user's account that The Planner is permitted to fetch Calendar Events from. Each has a stable Google id, a display summary (e.g. "Work", "Family"), and a background color.
_Avoid_: calendar, Google calendar, calendar list, feed

**Selected Source Calendars**:
The subset of the user's Source Calendars that The Planner currently fetches Calendar Events from. Defaults to the primary calendar on first connect.
_Avoid_: chosen calendars, enabled calendars, visible calendars

**Calendar Event**:
A Google Calendar event fetched from one of the Selected Source Calendars and rendered on the Calendar Surface while the Google Account Connection is active.
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

**Event Detail Popover**:
A transient, read-only overlay that presents the details of a single Calendar Event, including a link to that event in Google Calendar. It is summoned from the Calendar Surface but is a separate layer from it; it never allows creating, editing, or deleting events.
_Avoid_: Event modal, event popup, detail card, edit dialog

**Events Overflow**:
The "+N more" affordance shown in a Date Cell when its Calendar Events exceed the visible cap; it summons the Day Events Popover.
_Avoid_: More link, +x item, extra events, expand button, overflow menu

**Day Events Popover**:
A transient, read-only overlay that lists the Calendar Events for a single Date Cell. It is summoned from the Calendar Surface but is a separate layer from it; it never allows creating, editing, or deleting events.
_Avoid_: Day list, event popup, agenda, more-events modal, overflow menu

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
- A **Source Calendar** belongs to a connected **Google Account Connection**.
- **Selected Source Calendars** is the subset of **Source Calendars** the user has chosen; The Planner fetches **Calendar Events** only from these.
- A **Calendar Event** belongs to exactly one **Source Calendar**.
- A **Source Calendar Control** appears only while the **Google Account Connection** is connected.
- A **Source Calendar Control** opens the **Source Calendar Picker**.
- A **Source Calendar Picker** changes the **Selected Source Calendars**, which are persisted per device (ADR 0003).
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
- An **Event Detail Popover** presents exactly one **Calendar Event**.
- An **Event Detail Popover** is summoned from the **Calendar Surface** but is not part of it.
- An **Event Detail Popover** appears only while the **Google Account Connection** is connected.
- An **Events Overflow** appears in a **Date Cell** when its **Calendar Events** exceed the visible cap.
- An **Events Overflow** summons the **Day Events Popover**.
- A **Day Events Popover** presents the same **Calendar Events** or **Saved Busy Blocks** the **Calendar Surface** presents for that **Date Cell**.
- A **Day Events Popover** is summoned from the **Calendar Surface** but is not part of it.
- A **Day Events Popover** is a layout-overflow reveal, not a detail reveal: it carries no privacy boundary of its own.
- Selecting a **Calendar Event** in a **Day Events Popover** summons an **Event Detail Popover** for that event; this drill-through is available only while the **Google Account Connection** is connected.

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
- "calendar" used loosely to mean the pickable account-level entry; resolved: that concept is a **Source Calendar**, distinct from the **Calendar Surface**, **Calendar Header**, and **Calendar Event**.
