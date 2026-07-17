# Calendar Surface specification

Behavioral material extracted from the former single-context glossary during the delivery-stack restructuring. The canonical terminology now lives in the [Planning](../../../product/CONTEXT.md) and [Web Experience](../../CONTEXT.md) contexts.

## Relationships

- A **Calendar Header** belongs to exactly one **Calendar Surface**.
- A **Calendar Header** displays one **Product Name**.
- A **Calendar Header** displays one **Product Version**.
- A **Calendar Header** displays one **Visible Month**.
- A **Calendar Header** contains one **Account Control**.
- A **Calendar Header** contains one **Header Status**.
- An **Account Control** displays the **Google Account Connection** state.
- A **Google Account Connection** is either connected or disconnected.
- A **Google Account Connection** persists across browser sessions until Disconnect on This Device or ~30 days of inactivity (ADR 0005).
- A **Source Calendar** belongs to a connected **Google Account Connection**.
- **Selected Source Calendars** is the subset of **Source Calendars** the user has chosen; Planner fetches **Calendar Events** only from these.
- A **Calendar Event** belongs to exactly one **Source Calendar**.
- A **Calendar Event Refresh** covers the visible dates and the same one-month buffer used by scroll prefetch.
- A **Calendar Event Refresh** occurs when connected Planner returns to the foreground, regains connectivity, or remains visible for five minutes since its previous refresh.
- Periodic **Calendar Event Refreshes** pause while Planner is hidden.
- Dates outside a **Calendar Event Refresh** retain their previously fetched events; when scrolling approaches them, Planner presents those events immediately and refreshes them in place.
- A **Source Calendar Control** appears only while the **Google Account Connection** is connected.
- A **Source Calendar Control** opens the **Source Calendar Picker**.
- A **Source Calendar Picker** changes the **Selected Source Calendars**, which are persisted per device (ADR 0003).
- A **Calendar Event Refresh** begins with **Source Calendar Reconciliation**.
- **Source Calendar Reconciliation** retains existing selections that remain available, leaves newly available **Source Calendars** unselected, and removes selections that are no longer available.
- **Source Calendar Reconciliation** falls back to the primary **Source Calendar** when no previous selection remains available.
- A **Calendar Surface** presents the **Extended Calendar Range**.
- A **Calendar Surface** contains **Week Rows** ordered by date.
- A **Week Row** contains exactly seven **Date Cells**.
- A **Calendar Surface** displays **Calendar Events** when the **Google Account Connection** is connected.
- A **Calendar Surface** displays **Saved Busy Blocks** when the **Google Account Connection** is disconnected.
- A successful **Calendar Event Refresh** updates **Saved Busy Blocks** for each successfully refreshed **Source Calendar** without persisting event titles or details.
- A failed per-source refresh retains that **Source Calendar**'s previous **Saved Busy Blocks**.
- A **Visible Month** is derived from exactly one topmost visible **Week Row** in the **Calendar Surface**.
- A **Calendar Surface** contains one **Date Cell** for each consecutive date it presents.
- Each calendar month in the **Calendar Surface** has exactly one **Month Marker**.
- **Today** belongs to exactly one **Date Cell** in the **Calendar Surface**.
- A **Today Jump** targets the **Week Row** containing **Today**.
- A **Calendar Event** is either a **Calendar Event Bar** or a **Calendar Event Row**.
- A **Calendar Event Bar** spans one or more **Date Cells**.
- A **Calendar Event Bar** shows its title starting in the leftmost **Date Cell** and continuing across subsequent **Date Cells**.
- A **Calendar Event Bar** belongs to a vertical lane within each **Date Cell** it spans; bars are globally ordered by start date then start time then duration (longer first), and rows by start time.
- A **Calendar Event Row** belongs to exactly one **Date Cell**.
- A **Fetched Window** belongs to a connected **Google Account Connection** and is expanded by scroll-driven slab fetches.
- An **Event Detail Popover** presents exactly one **Calendar Event**.
- An **Event Detail Popover** is summoned from the **Calendar Surface** but is not part of it.
- An **Event Detail Popover** appears only while the **Google Account Connection** is connected.
- An **Events Overflow** appears in a **Date Cell** when its **Calendar Events** exceed the visible cap.
- An **Events Overflow** summons the **Day Events Popover**.
- A **Day Events Popover** presents the same **Calendar Events** or **Saved Busy Blocks** the **Calendar Surface** presents for that **Date Cell**.
- A **Day Events Popover** is summoned from the **Calendar Surface** but is not part of it.
- A **Day Events Popover** is a layout-overflow reveal, not a detail reveal: it carries no privacy boundary of its own.
- Selecting a **Calendar Event** in a **Day Events Popover** summons an **Event Detail Popover** for that event; this drill-through is available only while the **Google Account Connection** is connected.

## Example dialogue

> **Dev:** "Should the first version of the planner include tasks or events?"
> **Domain expert:** "No — the first version is only the **Calendar Surface**, anchored on **Today** in the viewer's local timezone."
>
> **Dev:** "What happens to Calendar Events after Disconnect on This Device?"
> **Domain expert:** "The Calendar Surface falls back to **Saved Busy Blocks** — placeholders that keep the shape of the calendar without exposing the original event titles."
>
> **Dev:** "If a **Calendar Event** changes in Google Calendar while Planner is open, when does it update?"
> **Domain expert:** "A **Calendar Event Refresh** updates visible and nearby dates when Planner returns to the foreground and every five minutes while it remains visible; distant dates refresh when scrolling approaches them."

## Flagged ambiguities

- "planner app" could mean a full planning product with events, tasks, and reminders; resolved: this first slice is the **Calendar Surface** only.
- "infinite scroll" could mean literally unbounded dates; resolved: the Calendar Surface uses an **Extended Calendar Range**.
- "event-free" was the original definition of the Calendar Surface; resolved: the Calendar Surface now displays **Calendar Events** while connected and **Saved Busy Blocks** while disconnected.
- "all-day" vs "multiday" in Google Calendar: an all-day event spanning multiple days is visually treated the same as a multiday timed event and rendered as a single **Calendar Event Bar** spanning all affected **Date Cells**.
- "calendar" used loosely to mean the pickable account-level entry; resolved: that concept is a **Source Calendar**, distinct from the **Calendar Surface**, **Calendar Header**, and **Calendar Event**.
- "Selected Source Calendars are changing" could mean the selection changed; resolved: the selection remains stable while upstream **Calendar Events** are added, removed, or edited, and a **Calendar Event Refresh** reflects those changes.
