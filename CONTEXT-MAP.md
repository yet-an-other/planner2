# Context Map

## Contexts

- [Planning](./product/CONTEXT.md) — defines Planner's platform-neutral Calendar Grid, Google Calendar, and event presentation language
- [Web Experience](./web/CONTEXT.md) — presents the planning experience through the web delivery stack
- [iOS Experience](./ios/CONTEXT.md) — presents the planning experience through the native iOS delivery stack

## Relationships

- **Web Experience → Planning**: Web Experience presents the Calendar Grid and uses Planning's Product Name, Product Version, Google Authorization Grant, Google Account Connection, Disconnect on This Device, Source Calendar, Primary Source Calendar, Selected Source Calendars, Source Calendar Reconciliation, Calendar Event, Event Color, Today, Calendar Event Refresh, Calendar Event Bar, Calendar Event Row, Events Overflow, Day Events Popover, Event Detail Popover, and Fetched Window language while owning its offline-display concepts.
- **iOS Experience → Planning**: iOS Experience presents Planning's Calendar Grid and uses its Product Name, Product Version, Today, Week Row, Date Cell, Extended Calendar Range, Month Marker, Visible Month, Today Jump, Google Authorization Grant, Google Account Connection, Disconnect on This Device, Source Calendar, Primary Source Calendar, Selected Source Calendars, Source Calendar Reconciliation, Calendar Event, Event Color, Fetched Window, Calendar Event Refresh, Calendar Event Bar, Calendar Event Row, Day Events Popover, Event Detail Popover, and Events Overflow language while owning the iOS Calendar Surface, iOS Source Calendar Control, iOS Source Calendar Picker, Stored Calendar Events, and native header presentation.
