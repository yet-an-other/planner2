import type {
  CalendarEventBar,
  CalendarEventRow,
  EventDetail,
} from '@/lib/google-calendar-events'

/**
 * Shared test factories for Calendar Events. They fill the nested `detail` and
 * normalized `timing` (PRD #003) with sensible defaults so layout/merge tests
 * stay terse and do not need to know about the popover's data shape.
 */

function emptyDetail(): EventDetail {
  return {
    htmlLink: null,
    location: null,
    description: null,
    attendees: [],
  }
}

type MakeBarInput = {
  id: string
  sourceCalendarId?: string
  title?: string
  eventType?: 'all-day' | 'multiday'
  date: Date
  endDate?: Date
  color?: string
  htmlLink?: string | null
  detail?: Partial<EventDetail>
}

export function makeBar(input: MakeBarInput): CalendarEventBar {
  const endDate = input.endDate ?? input.date
  const eventType = input.eventType ?? 'all-day'

  return {
    kind: 'bar',
    eventType,
    sourceCalendarId: input.sourceCalendarId ?? 'primary',
    id: input.id,
    title: input.title ?? input.id,
    date: input.date,
    endDate,
    color: input.color ?? '#2952a3',
    detail: { ...emptyDetail(), htmlLink: input.htmlLink ?? null, ...input.detail },
    timing: {
      start: input.date,
      end: endDate,
      isAllDay: eventType === 'all-day',
      isMultiday: endDate.getTime() > input.date.getTime(),
    },
  }
}

type MakeRowInput = {
  id: string
  sourceCalendarId?: string
  title?: string
  date: Date
  startTime?: string
  durationMinutes?: number
  color?: string
  htmlLink?: string | null
  detail?: Partial<EventDetail>
}

export function makeRow(input: MakeRowInput): CalendarEventRow {
  return {
    kind: 'row',
    sourceCalendarId: input.sourceCalendarId ?? 'primary',
    id: input.id,
    title: input.title ?? input.id,
    date: input.date,
    startTime: input.startTime ?? '09:00',
    durationMinutes: input.durationMinutes ?? 60,
    color: input.color ?? '#2952a3',
    detail: { ...emptyDetail(), htmlLink: input.htmlLink ?? null, ...input.detail },
    timing: {
      start: input.date,
      end: input.date,
      isAllDay: false,
      isMultiday: false,
    },
  }
}
