# Planning

The Planning context defines the platform-neutral language Planner uses to represent a connected Google account and its calendar data.

## Language

**Product Name**:
The public name of the product: Planner.
_Avoid_: App name, site title, brand label

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
