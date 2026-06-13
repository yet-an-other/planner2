# Planner

Planner is a personal planning product whose first slice is a calendar-only surface.

## Language

**Calendar Surface**:
A Monday-first, bidirectionally scrollable seven-column calendar grid that presents dates in an Extended Calendar Range for planning without event, task, or reminder content.
_Avoid_: Planner app, full planner, schedule manager, infinite calendar

**Calendar Header**:
The non-scrolling area that displays the Visible Month and Monday-first weekday labels for the Calendar Surface.
_Avoid_: Top bar, sticky header, current month header

**Visible Month**:
The month and year containing the first date in the topmost visible Week Row of the Calendar Surface.
_Avoid_: Current month, active month, shown month

**Week Row**:
A Monday-through-Sunday row of seven consecutive Date Cells in the Calendar Surface.
_Avoid_: Date row, calendar row

**Date Cell**:
A single date in the Calendar Surface, represented by its day-of-month number.
_Avoid_: Day card, calendar tile, date box

**Today**:
The current calendar date in the viewer's local timezone.
_Avoid_: Current day, system date, UTC date

**Extended Calendar Range**:
The complete Monday-through-Sunday Week Rows from the week containing ten years before Today through the week containing ten years after Today.
_Avoid_: Infinite range, endless dates, all dates

## Relationships

- A **Calendar Header** belongs to exactly one **Calendar Surface**.
- A **Calendar Header** displays one **Visible Month**.
- A **Calendar Surface** presents the **Extended Calendar Range**.
- A **Calendar Surface** contains **Week Rows** ordered by date.
- A **Week Row** contains exactly seven **Date Cells**.
- A **Visible Month** is derived from exactly one topmost visible **Week Row** in the **Calendar Surface**.
- A **Calendar Surface** contains one **Date Cell** for each consecutive date it presents.
- **Today** belongs to exactly one **Date Cell** in the **Calendar Surface**.

## Example dialogue

> **Dev:** "Should the first version of the planner include tasks or events?"
> **Domain expert:** "No — the first version is only the **Calendar Surface**, anchored on **Today** in the viewer's local timezone."

## Flagged ambiguities

- "planner app" could mean a full planning product with events, tasks, and reminders; resolved: this first slice is the **Calendar Surface** only.
- "infinite scroll" could mean literally unbounded dates; resolved: the Calendar Surface uses an **Extended Calendar Range**.
