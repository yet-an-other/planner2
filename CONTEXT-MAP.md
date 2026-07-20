# Context Map

## Contexts

- [Planning](./product/CONTEXT.md) — defines Planner's platform-neutral Calendar Grid and Google Calendar language
- [Web Experience](./web/CONTEXT.md) — presents the planning experience through the web delivery stack
- [iOS Experience](./ios/CONTEXT.md) — presents an event-free planning experience adapted for iOS

## Relationships

- **Web Experience → Planning**: Web Experience presents the Calendar Grid and uses Planning's Product Name, Product Version, Google Authorization Grant, Google Account Connection, Disconnect on This Device, source-calendar, event, and local-date language while owning its event presentation, refresh, and offline-display concepts.
- **iOS Experience → Planning**: iOS Experience presents Planning's Calendar Grid and uses its Product Name, Product Version, Today, Week Row, Date Cell, Extended Calendar Range, Month Marker, Visible Month, Today Jump, Google Authorization Grant, Google Account Connection, and Disconnect on This Device language while owning the event-free iOS Calendar Surface and native header presentation.
