# Web Experience

The Web Experience context defines the language of Planner's browser-based calendar surface, including its presentation and offline-display concepts.

## Language

**Calendar Surface**:
The browser presentation of the Calendar Grid, extended with the user's Calendar Events.
_Avoid_: Planner app, full planner, schedule manager, infinite calendar

**Calendar Header**:
The non-scrolling area that displays the Product Name, Visible Month, and Monday-first weekday labels for the Calendar Surface.
_Avoid_: Top bar, sticky header, current month header

**Account Control**:
The Calendar Header control that displays the Google Account Connection state and lets the user connect or Disconnect on This Device.
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

**Saved Busy Block**:
A privacy-preserving placeholder persisted by the Web Experience for offline use that retains a Calendar Event's timing and color but not its title.
_Avoid_: Cached event, local event, offline event
