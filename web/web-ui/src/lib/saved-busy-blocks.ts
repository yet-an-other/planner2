import type { CalendarEvent } from './google-calendar-events'

const STORAGE_KEY = 'planner.savedBusyBlocks'

type StoredBusyBlock =
  | {
      kind: 'bar'
      eventType: 'all-day' | 'multiday'
      start: string
      end: string
      color: string
    }
  | {
      kind: 'row'
      start: string
      end: string
      color: string
    }

/** Persist only the privacy-safe planning shape required by ADR 0001. */
export function persistSavedBusyBlocks(events: CalendarEvent[]): void {
  const blocks: StoredBusyBlock[] = events.map((event) =>
    event.kind === 'bar'
      ? {
          kind: 'bar',
          eventType: event.eventType,
          start: event.timing.start.toISOString(),
          end: event.timing.end.toISOString(),
          color: event.color,
        }
      : {
          kind: 'row',
          start: event.timing.start.toISOString(),
          end: event.timing.end.toISOString(),
          color: event.color,
        },
  )

  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(blocks))
  } catch {
    // Offline continuity is best-effort; storage failure never breaks the surface.
  }
}

/** Load privacy-safe placeholders for a disconnected Calendar Surface. */
export function loadSavedBusyBlocks(): CalendarEvent[] {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? '[]')
    if (!Array.isArray(parsed)) return []

    return parsed.flatMap((value, index): CalendarEvent[] => {
      if (!isStoredBusyBlock(value)) return []
      const start = new Date(value.start)
      const end = new Date(value.end)
      if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return []
      const id = `saved-${index}-${value.start}`
      const detail = { htmlLink: null, location: null, description: null, attendees: [] }

      if (value.kind === 'bar') {
        return [{
          kind: 'bar',
          eventType: value.eventType,
          sourceCalendarId: 'saved',
          id,
          title: 'Busy',
          date: localDate(start),
          endDate: localDate(end),
          color: value.color,
          detail,
          timing: {
            start,
            end,
            isAllDay: value.eventType === 'all-day',
            isMultiday: end.getTime() > start.getTime(),
          },
        }]
      }

      return [{
        kind: 'row',
        sourceCalendarId: 'saved',
        id,
        title: 'Busy',
        date: localDate(start),
        startTime: `${start.getHours().toString().padStart(2, '0')}:${start
          .getMinutes()
          .toString()
          .padStart(2, '0')}`,
        durationMinutes: Math.max(0, end.getTime() - start.getTime()) / 60_000,
        color: value.color,
        detail,
        timing: { start, end, isAllDay: false, isMultiday: false },
      }]
    })
  } catch {
    return []
  }
}

export function clearSavedBusyBlocks(): void {
  try {
    localStorage.removeItem(STORAGE_KEY)
  } catch {
    // Best-effort explicit cleanup.
  }
}

function isStoredBusyBlock(value: unknown): value is StoredBusyBlock {
  if (!value || typeof value !== 'object') return false
  const block = value as Record<string, unknown>
  return (
    (block.kind === 'bar' || block.kind === 'row') &&
    typeof block.start === 'string' &&
    typeof block.end === 'string' &&
    typeof block.color === 'string' &&
    (block.kind !== 'bar' ||
      block.eventType === 'all-day' ||
      block.eventType === 'multiday')
  )
}

function localDate(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}
