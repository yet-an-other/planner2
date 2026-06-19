export type CalendarEvent = CalendarEventBar | CalendarEventRow

export type CalendarEventBar = {
  kind: 'bar'
  eventType: 'all-day' | 'multiday'
  id: string
  title: string
  date: Date
  endDate: Date
  color: string
}

export type CalendarEventRow = {
  kind: 'row'
  id: string
  title: string
  date: Date
  startTime: string
  durationMinutes: number
  color: string
}

const GOOGLE_CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'
const DEFAULT_EVENT_COLOR = '#2952a3'

type GoogleCalendarListEntry = {
  backgroundColor?: string
}

type GoogleCalendarEventsResponse = {
  items?: GoogleCalendarEventResource[]
  nextPageToken?: string
}

type GoogleCalendarColorsResponse = {
  event?: Record<string, { background?: string }>
}

type GoogleCalendarEventResource = {
  attendees?: Array<{
    responseStatus?: string
    self?: boolean
  }>
  colorId?: string
  id?: string
  iCalUID?: string
  status?: string
  summary?: string
  start?: {
    date?: string
    dateTime?: string
  }
  end?: {
    date?: string
    dateTime?: string
  }
}

type CalendarEventFetchRange = {
  start: Date
  end: Date
}

export async function fetchPrimaryCalendarEvents(
  accessToken: string,
  range: CalendarEventFetchRange,
): Promise<CalendarEvent[]> {
  const [primaryCalendar, colorsResponse, eventsResponse] = await Promise.all([
    fetchPrimaryCalendar(accessToken),
    fetchGoogleCalendarColors(accessToken),
    fetchPrimaryCalendarEventResources(accessToken, range),
  ])

  return normalizeGoogleCalendarEvents(
    eventsResponse.items ?? [],
    primaryCalendar.backgroundColor ?? DEFAULT_EVENT_COLOR,
    colorsResponse.event ?? {},
  )
}

export function normalizeGoogleCalendarEvents(
  events: GoogleCalendarEventResource[],
  primaryCalendarColor: string,
  eventColors: Record<string, { background?: string }> = {},
): CalendarEvent[] {
  return events.flatMap<CalendarEvent>((event) => {
    if (event.status === 'cancelled' || isDeclinedByViewer(event)) {
      return []
    }

    const title = event.summary?.trim() || 'Busy'
    const color = getEventColor(event, primaryCalendarColor, eventColors)

    if (event.start?.date && event.end?.date) {
      const startDate = parseGoogleDate(event.start.date)
      const endDate = addDays(parseGoogleDate(event.end.date), -1)

      if (startDate > endDate) {
        return []
      }

      return [
        {
          kind: 'bar' as const,
          eventType: 'all-day' as const,
          id: event.id ?? event.iCalUID ?? `${event.start.date}-${title}`,
          title,
          date: startDate,
          endDate,
          color,
        },
      ]
    }

    if (!event.start?.dateTime || !event.end?.dateTime) {
      return []
    }

    const startsAt = new Date(event.start.dateTime)
    const endsAt = new Date(event.end.dateTime)
    const eventDate = toLocalDate(startsAt)

    if (!isSameCalendarDate(eventDate, toLocalDate(endsAt))) {
      return [
        {
          kind: 'bar' as const,
          eventType: 'multiday' as const,
          id: event.id ?? event.iCalUID ?? `${event.start.dateTime}-${title}`,
          title,
          date: eventDate,
          endDate: toLocalDate(endsAt),
          color,
        },
      ]
    }

    return [
      {
        kind: 'row' as const,
        id: event.id ?? event.iCalUID ?? `${event.start.dateTime}-${title}`,
        title,
        date: eventDate,
        startTime: formatEventStartTime(startsAt),
        durationMinutes: getDurationMinutes(startsAt, endsAt),
        color,
      },
    ]
  })
}

async function fetchPrimaryCalendar(accessToken: string) {
  const response = await fetch(
    `${GOOGLE_CALENDAR_API_BASE}/users/me/calendarList/primary`,
    {
      headers: getAuthHeaders(accessToken),
    },
  )

  if (!response.ok) {
    throw new Error('Primary calendar could not be loaded')
  }

  return (await response.json()) as GoogleCalendarListEntry
}

async function fetchGoogleCalendarColors(accessToken: string) {
  const response = await fetch(`${GOOGLE_CALENDAR_API_BASE}/colors`, {
    headers: getAuthHeaders(accessToken),
  })

  if (!response.ok) {
    throw new Error('Google Calendar colors could not be loaded')
  }

  return (await response.json()) as GoogleCalendarColorsResponse
}

async function fetchPrimaryCalendarEventResources(
  accessToken: string,
  range: CalendarEventFetchRange,
) {
  const items: GoogleCalendarEventResource[] = []
  let nextPageToken: string | undefined

  do {
    const response = await fetch(
      getPrimaryCalendarEventsUrl(range, nextPageToken),
      {
        headers: getAuthHeaders(accessToken),
      },
    )

    if (!response.ok) {
      throw new Error('Primary calendar events could not be loaded')
    }

    const page = (await response.json()) as GoogleCalendarEventsResponse
    items.push(...(page.items ?? []))
    nextPageToken = page.nextPageToken
  } while (nextPageToken)

  return { items }
}

function getPrimaryCalendarEventsUrl(
  range: CalendarEventFetchRange,
  pageToken?: string,
) {
  const url = new URL(`${GOOGLE_CALENDAR_API_BASE}/calendars/primary/events`)
  url.searchParams.set('singleEvents', 'true')
  url.searchParams.set('orderBy', 'startTime')
  url.searchParams.set('timeMin', range.start.toISOString())
  url.searchParams.set('timeMax', range.end.toISOString())

  if (pageToken) {
    url.searchParams.set('pageToken', pageToken)
  }

  return url
}

function getAuthHeaders(accessToken: string) {
  return {
    Authorization: `Bearer ${accessToken}`,
  }
}

function isDeclinedByViewer(event: GoogleCalendarEventResource) {
  return event.attendees?.some(
    (attendee) => attendee.self && attendee.responseStatus === 'declined',
  )
}

function getEventColor(
  event: GoogleCalendarEventResource,
  primaryCalendarColor: string,
  eventColors: Record<string, { background?: string }>,
) {
  return event.colorId
    ? (eventColors[event.colorId]?.background ?? primaryCalendarColor)
    : primaryCalendarColor
}

function parseGoogleDate(date: string) {
  const [year, month, day] = date.split('-').map(Number)

  return new Date(year, month - 1, day)
}

function getDurationMinutes(startsAt: Date, endsAt: Date) {
  return Math.max(0, endsAt.getTime() - startsAt.getTime()) / 60_000
}

function formatEventStartTime(date: Date) {
  return `${date.getHours().toString().padStart(2, '0')}:${date
    .getMinutes()
    .toString()
    .padStart(2, '0')}`
}

function addDays(date: Date, amount: number) {
  const next = new Date(date)
  next.setDate(date.getDate() + amount)
  return new Date(next.getFullYear(), next.getMonth(), next.getDate())
}

function toLocalDate(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function isSameCalendarDate(left: Date, right: Date) {
  return (
    left.getFullYear() === right.getFullYear() &&
    left.getMonth() === right.getMonth() &&
    left.getDate() === right.getDate()
  )
}
