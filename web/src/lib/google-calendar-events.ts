import { mergeCalendarEvents } from './merge-calendar-events'

export type CalendarEvent = CalendarEventBar | CalendarEventRow

export type CalendarEventBar = {
  kind: 'bar'
  eventType: 'all-day' | 'multiday'
  id: string
  title: string
  date: Date
  endDate: Date
  color: string
  /** Detail shown in the Event Detail Popover; memory-only while connected. */
  detail: EventDetail
  /** Normalized display timing so the popover never branches on `kind`. */
  timing: EventTiming
}

export type CalendarEventRow = {
  kind: 'row'
  id: string
  title: string
  date: Date
  startTime: string
  durationMinutes: number
  color: string
  /** Detail shown in the Event Detail Popover; memory-only while connected. */
  detail: EventDetail
  /** Normalized display timing so the popover never branches on `kind`. */
  timing: EventTiming
}

/**
 * Detail surfaced in the Event Detail Popover. All fields are memory-only while
 * the Google Account Connection is connected; none are persisted into Saved
 * Busy Blocks (see ADR 0001/0002).
 */
export type EventDetail = {
  /** Link to the event in Google Calendar. Null when Google omits it. */
  htmlLink: string | null
  /** Where the event takes place. Null when absent. */
  location: string | null
  /** Plain-text notes; HTML is stripped at normalization. Null when absent. */
  description: string | null
  /** Always an array; possibly empty when there are no invitees. */
  attendees: Attendee[]
}

/**
 * Uniform display timing computed once at normalization so the popover reads a
 * single shape regardless of bar-vs-row.
 */
export type EventTiming = {
  /** Full start instant (timed: with time; all-day: local midnight). */
  start: Date
  /** Full end instant (timed: with time; all-day: inclusive last day, midnight). */
  end: Date
  /** True when the event has no time component (all-day / multiday-all-day). */
  isAllDay: boolean
  /** True when the event spans more than one calendar date. */
  isMultiday: boolean
}

export type Attendee = {
  displayName: string | null
  email: string
  responseStatus: 'accepted' | 'declined' | 'tentative' | 'needsAction' | 'unknown'
}

const GOOGLE_CALENDAR_API_BASE = 'https://www.googleapis.com/calendar/v3'
const DEFAULT_EVENT_COLOR = '#2952a3'

/**
 * Google auto-appends this boilerplate to events it creates automatically
 * (flights, hotel reservations, etc.). It carries no user value, so it is
 * stripped from the description at normalization. The g.co/calendar link may
 * sit on the same line or wrap; `\s*` tolerates either.
 */
const GOOGLE_AUTO_EVENT_BOILERPLATE =
  /To see detailed information for automatically created events like this one, use the official Google Calendar app\.\s*https:\/\/g\.co\/calendar/g

type GoogleCalendarListEntry = {
  id?: string
  summary?: string
  backgroundColor?: string
  primary?: boolean
  accessRole?: string
  hidden?: boolean
  deleted?: boolean
}

type GoogleCalendarListResponse = {
  items?: GoogleCalendarListEntry[]
}

type GoogleCalendarEventsResponse = {
  items?: GoogleCalendarEventResource[]
  nextPageToken?: string
}

type GoogleCalendarColorsResponse = {
  event?: Record<string, { background?: string }>
}

export type GoogleCalendarEventResource = {
  attendees?: Array<{
    responseStatus?: string
    self?: boolean
    displayName?: string
    email?: string
  }>
  colorId?: string
  htmlLink?: string
  id?: string
  iCalUID?: string
  location?: string
  description?: string
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

/**
 * A Google Calendar in the user's account that The Planner is permitted to fetch
 * Calendar Events from. See CONTEXT.md.
 */
export type SourceCalendar = {
  id: string
  summary: string
  backgroundColor: string
  primary: boolean
}

/** One Selected Source Calendar's fetch outcome: its events, or that it failed. */
type CalendarFetchOutcome =
  | { calendarId: string; events: CalendarEvent[] }
  | { calendarId: string; failed: true }

/**
 * The result of fetching Calendar Events across the Selected Source Calendars.
 * The counts let the caller distinguish total failure (hard error) from partial
 * failure (non-fatal warning) without re-counting itself.
 */
export type FetchCalendarEventsResult = {
  events: CalendarEvent[]
  failedCalendarCount: number
  totalCalendarCount: number
}

const READABLE_ACCESS_ROLES = new Set(['reader', 'writer', 'owner'])

/**
 * Thrown by the Google fetch helpers on a 401 so the SPA can refresh the access
 * token and retry the call exactly once (see `withTokenRefresh`). Distinct from
 * other errors, which are not retryable.
 */
export class UnauthorizedError extends Error {
  constructor() {
    super('Google access token is not authorized')
    this.name = 'UnauthorizedError'
  }
}

/** Throws `UnauthorizedError` on 401 (retryable) or a generic error otherwise. */
function assertOk(response: Response, fallbackMessage: string) {
  if (response.status === 401) {
    throw new UnauthorizedError()
  }
  if (!response.ok) {
    throw new Error(fallbackMessage)
  }
}

/**
 * Fetches the user's Source Calendars — every readable, non-hidden calendar in
 * the Google account. Replaces the old primary-only lookup; the primary
 * calendar's color is read from this list.
 */
export async function fetchCalendarList(
  accessToken: string,
): Promise<SourceCalendar[]> {
  const response = await fetch(
    `${GOOGLE_CALENDAR_API_BASE}/users/me/calendarList`,
    {
      headers: getAuthHeaders(accessToken),
    },
  )

  assertOk(response, 'Calendar list could not be loaded')

  const body = (await response.json()) as GoogleCalendarListResponse

  return (body.items ?? [])
    .filter(
      (entry) =>
        !entry.deleted &&
        !entry.hidden &&
        READABLE_ACCESS_ROLES.has(entry.accessRole ?? ''),
    )
    .map((entry) => ({
      id: entry.id ?? '',
      summary: entry.summary?.trim() || entry.id || 'Untitled calendar',
      backgroundColor: entry.backgroundColor ?? DEFAULT_EVENT_COLOR,
      primary: entry.primary === true,
    }))
    .filter((calendar) => calendar.id !== '')
}

/**
 * Pure assembly of per-calendar fetch outcomes into a single result: merges the
 * successful calendars' events (id-based dedup, first-wins) and counts the
 * failures so the caller can tell partial from total failure.
 */
export function assembleCalendarEvents(
  outcomes: CalendarFetchOutcome[],
): FetchCalendarEventsResult {
  let failedCalendarCount = 0
  let merged: CalendarEvent[] = []

  for (const outcome of outcomes) {
    if ('failed' in outcome) {
      failedCalendarCount += 1
      continue
    }

    merged = mergeCalendarEvents(merged, outcome.events)
  }

  return {
    events: merged,
    failedCalendarCount,
    totalCalendarCount: outcomes.length,
  }
}

/** Injectable network collaborators for `fetchSourceCalendarEvents`. */
export type FetchSourceCalendarEventsDeps = {
  fetchColors?: (accessToken: string) => Promise<GoogleCalendarColorsResponse>
  fetchCalendarEvents?: (
    accessToken: string,
    calendarId: string,
    range: CalendarEventFetchRange,
  ) => Promise<GoogleCalendarEventResource[]>
}

/**
 * Fetches Calendar Events from every Selected Source Calendar in parallel,
 * coloring each event by its own calendar (an explicit Google event color still
 * wins) and merging the results. A single calendar failing does not fail the
 * whole fetch — it is counted as a failure so the caller can warn; only the
 * global colors fetch (or a thrown bug) rejects the promise.
 */
export async function fetchSourceCalendarEvents(
  accessToken: string,
  calendars: SourceCalendar[],
  range: CalendarEventFetchRange,
  {
    fetchColors = fetchGoogleCalendarColors,
    fetchCalendarEvents = fetchCalendarEventResources,
  }: FetchSourceCalendarEventsDeps = {},
): Promise<FetchCalendarEventsResult> {
  if (calendars.length === 0) {
    return { events: [], failedCalendarCount: 0, totalCalendarCount: 0 }
  }

  const eventColors = (await fetchColors(accessToken)).event ?? {}

  const outcomes = await Promise.all(
    calendars.map(
      async (calendar): Promise<CalendarFetchOutcome> => {
        try {
          const resources = await fetchCalendarEvents(
            accessToken,
            calendar.id,
            range,
          )
          return {
            calendarId: calendar.id,
            events: normalizeGoogleCalendarEvents(
              resources,
              calendar.backgroundColor,
              eventColors,
            ),
          }
        } catch (error) {
          if (error instanceof UnauthorizedError) {
            throw error
          }
          return { calendarId: calendar.id, failed: true }
        }
      },
    ),
  )

  return assembleCalendarEvents(outcomes)
}

export function normalizeGoogleCalendarEvents(
  events: GoogleCalendarEventResource[],
  calendarColor: string,
  eventColors: Record<string, { background?: string }> = {},
): CalendarEvent[] {
  return events.flatMap<CalendarEvent>((event) => {
    if (event.status === 'cancelled' || isDeclinedByViewer(event)) {
      return []
    }

    const title = event.summary?.trim() || 'Busy'
    const color = getEventColor(event, calendarColor, eventColors)
    const detail: EventDetail = {
      htmlLink: event.htmlLink ?? null,
      location: event.location?.trim() || null,
      description: buildDescription(event.description),
      attendees: mapAttendees(event.attendees),
    }

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
          detail,
          timing: {
            start: startDate,
            end: endDate,
            isAllDay: true,
            isMultiday: endDate.getTime() > startDate.getTime(),
          },
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
          detail,
          timing: {
            start: startsAt,
            end: endsAt,
            isAllDay: false,
            isMultiday: true,
          },
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
        detail,
        timing: {
          start: startsAt,
          end: endsAt,
          isAllDay: false,
          isMultiday: false,
        },
      },
    ]
  })
}

async function fetchGoogleCalendarColors(accessToken: string) {
  const response = await fetch(`${GOOGLE_CALENDAR_API_BASE}/colors`, {
    headers: getAuthHeaders(accessToken),
  })

  assertOk(response, 'Google Calendar colors could not be loaded')

  return (await response.json()) as GoogleCalendarColorsResponse
}

async function fetchCalendarEventResources(
  accessToken: string,
  calendarId: string,
  range: CalendarEventFetchRange,
): Promise<GoogleCalendarEventResource[]> {
  const items: GoogleCalendarEventResource[] = []
  let nextPageToken: string | undefined

  do {
    const response = await fetch(
      getCalendarEventsUrl(calendarId, range, nextPageToken),
      {
        headers: getAuthHeaders(accessToken),
      },
    )

    assertOk(response, 'Calendar events could not be loaded')

    const page = (await response.json()) as GoogleCalendarEventsResponse
    items.push(...(page.items ?? []))
    nextPageToken = page.nextPageToken
  } while (nextPageToken)

  return items
}

function getCalendarEventsUrl(
  calendarId: string,
  range: CalendarEventFetchRange,
  pageToken?: string,
) {
  const url = new URL(
    `${GOOGLE_CALENDAR_API_BASE}/calendars/${encodeURIComponent(calendarId)}/events`,
  )
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

const KNOWN_RESPONSE_STATUSES = new Set<Attendee['responseStatus']>([
  'accepted',
  'declined',
  'tentative',
  'needsAction',
])

/** Maps Google attendees to the popover's closed-union Attendee shape. */
function mapAttendees(
  attendees: GoogleCalendarEventResource['attendees'],
): Attendee[] {
  if (!attendees) {
    return []
  }

  return attendees
    .map((attendee) => ({
      displayName: attendee.displayName?.trim() || null,
      email: attendee.email?.trim() ?? '',
      responseStatus:
        attendee.responseStatus &&
        KNOWN_RESPONSE_STATUSES.has(
          attendee.responseStatus as Attendee['responseStatus'],
        )
          ? (attendee.responseStatus as Attendee['responseStatus'])
          : 'unknown',
    }))
    .filter((attendee) => attendee.displayName !== null || attendee.email !== '')
}

/**
 * Renders the Google description into plain text by stripping HTML via the DOM.
 * Plain text avoids XSS risk and any tracking beacons an organizer may embed.
 * Safe because the app is a browser SPA (no SSR); works in jsdom tests too.
 *
 * Also strips Google's auto-injected "automatically created events" boilerplate
 * (it carries no user value and only clutters the popover).
 */
function buildDescription(description: string | undefined): string | null {
  if (!description) {
    return null
  }

  const element = document.createElement('div')
  element.innerHTML = description
  const text = (element.textContent ?? '')
    .replace(GOOGLE_AUTO_EVENT_BOILERPLATE, '')
    .trim()
  return text || null
}

function getEventColor(
  event: GoogleCalendarEventResource,
  calendarColor: string,
  eventColors: Record<string, { background?: string }>,
) {
  return event.colorId
    ? (eventColors[event.colorId]?.background ?? calendarColor)
    : calendarColor
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
