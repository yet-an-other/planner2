import type {
  CalendarEvent,
  CalendarFetchOutcome,
  FetchCalendarEventsResult,
} from './google-calendar-events'
import { calendarEventKey, mergeCalendarEvents } from './merge-calendar-events'

export type DateRange = { start: Date; end: Date }

/**
 * Replaces an intersecting range independently for each successful Source
 * Calendar. Failed sources and events outside the requested range are retained.
 */
export function replaceCalendarEventRange(
  existing: CalendarEvent[],
  result: FetchCalendarEventsResult,
  range: DateRange,
  requestedSourceIds: string[] = [],
): CalendarEvent[] {
  const outcomes = outcomesFor(result, requestedSourceIds)
  const successfulIds = new Set(
    outcomes.flatMap((outcome) => ('failed' in outcome ? [] : [outcome.calendarId])),
  )
  const retained = existing.filter(
    (event) =>
      !successfulIds.has(event.sourceCalendarId) ||
      !eventIntersectsRange(event, range),
  )
  const previousByKey = new Map(
    existing.map((event) => [calendarEventKey(event), event]),
  )
  const incoming = outcomes.flatMap((outcome) =>
    'failed' in outcome
      ? []
      : outcome.events.map((event) => {
          const previous = previousByKey.get(calendarEventKey(event))
          return result.colorMetadataAvailable === false && previous
            ? { ...event, color: previous.color }
            : event
        }),
  )
  return mergeCalendarEvents(retained, incoming)
}

function outcomesFor(
  result: FetchCalendarEventsResult,
  requestedSourceIds: string[],
): CalendarFetchOutcome[] {
  if (result.outcomes) return result.outcomes

  if (result.failedCalendarCount === result.totalCalendarCount) {
    return requestedSourceIds.map((calendarId) => ({ calendarId, failed: true }))
  }

  if (result.failedCalendarCount === 0) {
    return requestedSourceIds.map((calendarId) => ({
      calendarId,
      events: result.events.filter(
        (event) => event.sourceCalendarId === calendarId,
      ),
    }))
  }

  // Legacy injected adapters cannot identify an empty successful calendar in a
  // partial result. Treat sources represented in the result as successful and
  // retain every other source rather than risk destructive replacement.
  const successfulIds = new Set(result.events.map((event) => event.sourceCalendarId))
  return requestedSourceIds.map((calendarId) =>
    successfulIds.has(calendarId)
      ? {
          calendarId,
          events: result.events.filter(
            (event) => event.sourceCalendarId === calendarId,
          ),
        }
      : { calendarId, failed: true },
  )
}

export function eventIntersectsRange(
  event: CalendarEvent,
  range: DateRange,
): boolean {
  const start = event.kind === 'bar' ? event.date : event.timing.start
  const end = event.kind === 'bar' ? event.endDate : event.timing.end
  return start.getTime() <= range.end.getTime() && end.getTime() >= range.start.getTime()
}
