# Web Experience

The Web Experience context defines the language of Planner's browser-based calendar surface, including its presentation, refresh, and offline-display concepts.

## Language

**Fetched Window**:
The continuous date range bounded by the earliest and latest dates fetched from Google Calendar.
_Avoid_: Fetched cache, loaded range, data window

**Calendar Surface**:
The browser presentation of the Calendar Grid, extended with the user's Calendar Events.
_Avoid_: Planner app, full planner, schedule manager, infinite calendar

**Calendar Header**:
The non-scrolling area that displays the Product Name, Visible Month, and Monday-first weekday labels for the Calendar Surface.
_Avoid_: Top bar, sticky header, current month header

**Product Version**:
The public version identifier displayed with the Product Name.
_Avoid_: Build number, package version, release tag

**Account Control**:
The Calendar Header control that displays the Google Account Connection state and lets the user connect or manage the connected account.
_Avoid_: Login button, profile button, auth widget

**Source Calendar Control**:
The connected-only Calendar Header control that opens the Source Calendar Picker.
_Avoid_: Settings button, calendar filter, gear, preferences

**Source Calendar Picker**:
A modal dialog that lists the user's Source Calendars and supports changing the Selected Source Calendars with explicit Save and Cancel actions.
_Avoid_: Settings modal, calendar dialog, preferences screen

**Header Status**:
A Calendar Header area for short connection information, progress messages, or errors related to the Calendar Surface.
_Avoid_: Toast, alert, notification bar

**Calendar Event Refresh**:
A replacement of Calendar Events for the visible dates and the one-month scroll-prefetch buffer with their current state from the Selected Source Calendars.
_Avoid_: Page refresh, reload, calendar refresh, sync

**Calendar Event Bar**:
A visual representation of a multiday or all-day Calendar Event rendered as a solid colored bar spanning one or more Date Cells.
_Avoid_: Event strip, block, banner

**Calendar Event Row**:
A visual representation of an intraday Calendar Event rendered inside a single Date Cell with a dot, start time, and title.
_Avoid_: Event chip, pill, card

**Saved Busy Block**:
A privacy-preserving placeholder persisted by the Web Experience for offline use that retains a Calendar Event's timing and color but not its title.
_Avoid_: Cached event, local event, offline event

**Event Detail Popover**:
A transient, read-only overlay that presents the details of one Calendar Event, including a link to that event in Google Calendar.
_Avoid_: Event modal, event popup, detail card, edit dialog

**Events Overflow**:
The “+N more” affordance shown in a Date Cell when its Calendar Events exceed the visible cap.
_Avoid_: More link, +x item, extra events, expand button, overflow menu

**Day Events Popover**:
A transient, read-only overlay that lists the Calendar Events for one Date Cell.
_Avoid_: Day list, event popup, agenda, more-events modal, overflow menu
