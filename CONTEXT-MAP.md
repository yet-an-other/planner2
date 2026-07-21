# Context Map

## Contexts

- [Planning](./product/CONTEXT.md) — defines Planner's platform-neutral Calendar Grid, Google Calendar, and event presentation language
- [Web Experience](./web/CONTEXT.md) — presents the planning experience through the web delivery stack
- [iOS Experience](./ios/CONTEXT.md) — presents the planning experience through the native iOS delivery stack

## Relationships

- **Web Experience → Planning**: Web Experience presents the Calendar Grid and uses Planning's Product Name, Product Version, Google Authorization Grant, Google Account Connection, Disconnect on This Device, Source Calendar, Calendar Event, Event Color, Today, Calendar Event Bar, Calendar Event Row, Events Overflow, and Fetched Window language while owning its event popover, refresh, and offline-display concepts.
- **iOS Experience → Planning**: iOS Experience presents Planning's Calendar Grid and uses its Product Name, Product Version, Today, Week Row, Date Cell, Extended Calendar Range, Month Marker, Visible Month, Today Jump, Google Authorization Grant, Google Account Connection, Disconnect on This Device, Source Calendar, Calendar Event, Event Color, Fetched Window, Calendar Event Bar, Calendar Event Row, and Events Overflow language while owning the iOS Calendar Surface and native header presentation.
