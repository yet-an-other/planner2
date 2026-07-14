# Day Events Popover is a non-gated overflow reveal

When a Date Cell's Calendar Events exceed the visible cap, its **Events Overflow** ("+N more") summons a new **Day Events Popover** — a separate-layer, non-modal list of every Calendar Event attributed to that cell — rather than overloading the Event Detail Popover. The list mirrors the cell's own stacking (Calendar Event Bars in lane order, then Calendar Event Rows by start time) and presents the same Calendar Events or Saved Busy Blocks the Calendar Surface presents for that Date Cell. Selecting an event in it opens the Event Detail Popover, close-and-open: the two overlays are mutually exclusive (at most one separate-layer overlay open at a time).

Crucially, the Day Events Popover **carries no privacy boundary of its own**. It reveals only what the Calendar Surface already presents (clipped to the visible cap), so it is **not connection-gated** — it shows Saved Busy Blocks unchanged when they ship. The privacy boundary lives entirely on the connected-only Event Detail Popover (ADR 0002), so the drill-through from list item to detail is the *only* connection-gated part. This separates two concerns that are easy to conflate: a layout-overflow reveal (no new disclosure) versus a title/detail reveal (the disclosure the boundary guards).

The Day Events Popover reuses the Event Detail Popover's exact separate-layer contract: anchored to its trigger (the Events Overflow) via the shared placement machinery, dismissed by close button, Escape, outside-click, and surface-scroll. It does **not** close on disconnect (it is not connection-gated), unlike its sibling.

## Consequences

- The Calendar Surface gains a second separate-layer overlay. It is a sibling of, and mutually exclusive with, the Event Detail Popover; interaction is unified under one anchor/dismiss/focus-return path rather than two divergent ones.
- The write-read-only invariant from ADR 0002 is preserved: the Day Events Popover never creates, edits, or deletes events, and it carries no new persistence. List contents are memory-only while connected.
- "Overflow" now has two senses: the user-facing **Events Overflow** affordance (this ADR) and the internal `overflow` layout artifact in the event layout engine. These are related but distinct; the glossary names the affordance, the layout engine names the artifact.
- Until Saved Busy Blocks are implemented (ADR 0001, not yet built), the Day Events Popover is only ever observable while connected, because disconnected cells are empty. The non-gated decision is forward-looking: it will work for Saved Busy Blocks automatically when they arrive.

## Alternatives considered

- **Overload the Event Detail Popover with a list mode.** Rejected: it muddies a clean one-event concept that is already wired deeply into placement, focus, and tests; a list is a genuinely different thing from a detail view. Splitting "single mode" vs "list mode" inside one component would entangle two concepts.
- **Connection-gate the Day Events Popover (match its sibling).** Rejected: it discloses nothing the Calendar Surface does not already present, so there is no privacy boundary to enforce. Gating it would also prevent it from ever revealing Saved Busy Blocks, contradicting the reveal-not-disclose intent.
- **Stack the Day Events Popover behind the Event Detail Popover** (so closing detail returns to the list for browsing). Rejected: breaks single cardinality, adds z-order and nested dismiss/focus rules, and erodes the calm-overview identity from ADR 0002. Re-opening the list via "+N more" is one cheap click.

## References

- PRD #005 — Day Events Popover (the feature spec enabled by this decision).
- ADR 0001 — Persist Saved Busy Blocks without event titles (the privacy principle this decision leans on; the Saved Busy Blocks path this popover will eventually serve).
- ADR 0002 — Permit a read-only Event Detail Popover (the separate-layer pattern and the connected-only detail boundary this extends).
