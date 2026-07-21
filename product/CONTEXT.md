# Planning

The Planning context defines Planner's platform-neutral language for its shared calendar structure, connected Google accounts, calendar data, and event presentation.

## Language

**Product Name**:
The public name of the product: Planner.
_Avoid_: App name, site title, brand label

**Product Version**:
The public version identifier displayed with the Product Name.
_Avoid_: Build number, package version, release tag

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

**Google Authorization Grant**:
Google's project-wide permission for Planner's OAuth clients to identify a user and read their Google Calendar. One grant can support Google Account Connections in multiple app installations and browser profiles.
_Avoid_: Google Account Connection, session, credentials

**Google Account Connection**:
The local association between one Planner app installation or browser profile and one Google account, through which that client can identify the user and read their Google Calendar under a Google Authorization Grant.
_Avoid_: Login, Google auth, OAuth token

**Disconnect on This Device**:
An action that removes the Google Account Connection from the current app installation or browser profile without revoking the Google Authorization Grant or affecting connections elsewhere.
_Avoid_: Disconnect, logout, sign out everywhere, revoke access

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

**Event Color**:
The color of a Calendar Event: its explicit Google event color when one is set, otherwise the background color of its Source Calendar.
_Avoid_: Event tint, calendar color, event background

**Fetched Window**:
The continuous date range bounded by the earliest and latest dates fetched from Google Calendar.
_Avoid_: Fetched cache, loaded range, data window

**Calendar Event Bar**:
A visual representation of a multiday or all-day Calendar Event rendered as a solid colored bar spanning one or more Date Cells.
_Avoid_: Event strip, block, banner

**Calendar Event Row**:
A visual representation of an intraday Calendar Event rendered inside a single Date Cell with a dot, start time, and title.
_Avoid_: Event chip, pill, card

**Events Overflow**:
The “+N more” indicator shown in a Date Cell when its Calendar Events exceed the visible cap. Each delivery experience decides whether it summons anything.
_Avoid_: More link, +x item, extra events, expand button, overflow menu

**Today**:
The current calendar date in the viewer's local timezone.
_Avoid_: Current day, system date, UTC date
