# Planning

The Planning context defines Planner's platform-neutral language for its shared calendar structure, connected Google accounts, and calendar data.

## Language

**Product Name**:
The public name of the product: Planner.
_Avoid_: App name, site title, brand label

**Calendar Grid**:
Planner's shared, Gregorian, Monday-first, seven-column sequence of consecutive local dates. It scrolls continuously in both vertical directions and is presented by each delivery experience in a platform-appropriate form.
_Avoid_: Calendar Surface, date picker, month calendar

**Week Row**:
A Monday-through-Sunday row of seven consecutive Date Cells in the Calendar Grid.
_Avoid_: Date row, calendar row

**Date Cell**:
A single local date in the Calendar Grid.
_Avoid_: Day card, calendar tile, date box

**Extended Calendar Range**:
The complete Week Rows from the week containing ten years before Today through the week containing ten years after Today.
_Avoid_: Infinite range, endless dates, all dates

**Month Marker**:
The first Date Cell of a calendar month, labeled with that month's short name.
_Avoid_: Month divider, month label, month start

**Visible Month**:
The month and year containing the first date in the topmost visible Week Row of the Calendar Grid.
_Avoid_: Current month, active month, shown month

**Today Jump**:
An action that returns the Calendar Grid to the Week Row containing Today.
_Avoid_: Back to today, scroll home, month click

**Google Account Connection**:
The user's authorization for Planner to identify them with Google and read their Google Calendar.
_Avoid_: Login, Google auth, OAuth token

**Source Calendar**:
A Google Calendar in the user's account that Planner is permitted to read. It has a stable Google id, a display summary, and a background color.
_Avoid_: Calendar, Google calendar, calendar list, feed

**Selected Source Calendars**:
The subset of the user's Source Calendars that Planner uses as sources for Calendar Events.
_Avoid_: Chosen calendars, enabled calendars, visible calendars

**Source Calendar Reconciliation**:
The alignment of Planner's Source Calendars and Selected Source Calendars with the calendars currently available from Google.
_Avoid_: Calendar sync, selection reset, calendar reload

**Calendar Event**:
A Google Calendar event available to Planner from one of the Selected Source Calendars.
_Avoid_: Event item, schedule entry, appointment

**Today**:
The current calendar date in the viewer's local timezone.
_Avoid_: Current day, system date, UTC date
