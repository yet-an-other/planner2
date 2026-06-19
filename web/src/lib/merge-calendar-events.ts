import type { CalendarEvent } from './google-calendar-events'

/**
 * Merge two sets of Calendar Events, dropping any incoming event whose Google
 * Calendar id is already present in the existing set.
 *
 * Overlapping slab fetches can return the same event twice; this collapses
 * them to a single entry. The existing entry wins — it is never overwritten by
 * an incoming duplicate — so ordering and identity stay stable across merges.
 */
export function mergeCalendarEvents(
  existing: CalendarEvent[],
  incoming: CalendarEvent[],
): CalendarEvent[] {
  const seenIds = new Set(existing.map((event) => event.id))
  const merged = [...existing]

  for (const event of incoming) {
    if (seenIds.has(event.id)) {
      continue
    }
    seenIds.add(event.id)
    merged.push(event)
  }

  return merged
}
