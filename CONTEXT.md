# Planner

Planner is a personal planning product whose first slice is a calendar-only surface.

## Language

**Calendar Surface**:
A Monday-first, bidirectionally scrollable seven-column calendar grid that presents dates in an Extended Calendar Range for planning without event, task, or reminder content.
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
- A **Visible Month** is derived from exactly one topmost visible **Week Row** in the **Calendar Surface**.
- A **Calendar Surface** contains one **Date Cell** for each consecutive date it presents.
- Each calendar month in the **Calendar Surface** has exactly one **Month Marker**.
- **Today** belongs to exactly one **Date Cell** in the **Calendar Surface**.
- A **Today Jump** targets the **Week Row** containing **Today**.

## Example dialogue

> **Dev:** "Should the first version of the planner include tasks or events?"
> **Domain expert:** "No — the first version is only the **Calendar Surface**, anchored on **Today** in the viewer's local timezone."

## Flagged ambiguities

- "planner app" could mean a full planning product with events, tasks, and reminders; resolved: this first slice is the **Calendar Surface** only.
- "infinite scroll" could mean literally unbounded dates; resolved: the Calendar Surface uses an **Extended Calendar Range**.
