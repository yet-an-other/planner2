# Context Map

## Contexts

- [Planning](./product/CONTEXT.md) — defines Planner's platform-neutral Calendar Grid and Google Calendar language
- [Web Experience](./web/CONTEXT.md) — presents the planning experience through the web delivery stack
- [iOS Experience](./ios/CONTEXT.md) — presents an event-free planning experience adapted for iOS

## Relationships

- **Web Experience → Planning**: Web Experience presents the Calendar Grid and uses Planning's account, source-calendar, event, and local-date language while owning its event presentation, refresh, and offline-display concepts.
- **iOS Experience → Planning**: iOS Experience presents the Calendar Grid and uses Planning's Product Name and Today while owning its event-free presentation concepts.
