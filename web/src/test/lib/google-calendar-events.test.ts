import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  assembleCalendarEvents,
  fetchCalendarList,
  fetchSourceCalendarEvents,
  normalizeGoogleCalendarEvents,
  UnauthorizedError,
} from '@/lib/google-calendar-events'
import { makeBar } from './calendar-events.factory'

const PRIMARY_COLOR = '#2952a3'
const JUNE_17 = new Date(2026, 5, 17)
const RANGE = { start: new Date(2026, 5, 17), end: new Date(2026, 5, 18) }

describe('normalizeGoogleCalendarEvents', () => {
  it('carries the htmlLink into the nested EventDetail of an all-day bar', () => {
    const events = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-1',
          summary: 'Team Lunch',
          htmlLink: 'https://www.google.com/calendar/event?eid=evt-1',
          start: { date: '2026-06-15' },
          end: { date: '2026-06-16' },
        },
      ],
      PRIMARY_COLOR,
    )

    expect(events).toHaveLength(1)
    const [event] = events
    expect(event.kind).toBe('bar')
    if (event.kind !== 'bar') return
    expect(event.detail.htmlLink).toBe(
      'https://www.google.com/calendar/event?eid=evt-1',
    )
  })

  it('computes an all-day EventTiming for an all-day single-day bar', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-1',
          summary: 'Team Lunch',
          start: { date: '2026-06-15' },
          end: { date: '2026-06-16' },
        },
      ],
      PRIMARY_COLOR,
    )

    expect(event.kind).toBe('bar')
    if (event.kind !== 'bar') return
    expect(event.timing.isAllDay).toBe(true)
    expect(event.timing.isMultiday).toBe(false)
  })

  it('computes a multiday EventTiming that preserves times for a midnight-crossing bar', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-2',
          summary: 'Late shift',
          start: { dateTime: '2026-06-15T23:00:00' },
          end: { dateTime: '2026-06-16T01:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    expect(event.kind).toBe('bar')
    if (event.kind !== 'bar') return
    expect(event.timing.isAllDay).toBe(false)
    expect(event.timing.isMultiday).toBe(true)
    expect(event.timing.start).toEqual(new Date('2026-06-15T23:00:00'))
    expect(event.timing.end).toEqual(new Date('2026-06-16T01:00:00'))
  })

  it('computes a single-day timed EventTiming for an intraday row', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-3',
          summary: 'Design Review',
          htmlLink: 'https://www.google.com/calendar/event?eid=evt-3',
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    expect(event.kind).toBe('row')
    if (event.kind !== 'row') return
    expect(event.timing.isAllDay).toBe(false)
    expect(event.timing.isMultiday).toBe(false)
    expect(event.detail.htmlLink).toBe(
      'https://www.google.com/calendar/event?eid=evt-3',
    )
  })

  it('treats missing location, description, and attendees as null/empty', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-4',
          summary: 'Sparse event',
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    if (event.kind !== 'row') return
    expect(event.detail.location).toBeNull()
    expect(event.detail.description).toBeNull()
    expect(event.detail.attendees).toEqual([])
  })

  it('carries location, description, and attendees through into the EventDetail', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-rich',
          summary: 'Offsite',
          location: 'Conference Room A',
          description: 'Quarterly planning',
          attendees: [
            {
              email: 'ada@example.com',
              displayName: 'Ada',
              responseStatus: 'accepted',
            },
            { email: 'bob@example.com', responseStatus: 'declined' },
          ],
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    if (event.kind !== 'row') return
    expect(event.detail.location).toBe('Conference Room A')
    expect(event.detail.description).toBe('Quarterly planning')
    expect(event.detail.attendees).toEqual([
      {
        displayName: 'Ada',
        email: 'ada@example.com',
        responseStatus: 'accepted',
      },
      {
        displayName: null,
        email: 'bob@example.com',
        responseStatus: 'declined',
      },
    ])
  })

  it('strips HTML from the description and keeps plain text', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-html',
          summary: 'Sync',
          description: '<b>Bring</b> <a href="x">notes</a> &amp; laptop',
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    if (event.kind !== 'row') return
    expect(event.detail.description).toBe('Bring notes & laptop')
  })

  it('strips the Google "automatically created events" boilerplate from the description', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-boiler',
          summary: 'Flight',
          description:
            'UA 123 SFO→JFK\n\nTo see detailed information for automatically created events like this one, use the official Google Calendar app. https://g.co/calendar',
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    if (event.kind !== 'row') return
    expect(event.detail.description).toBe('UA 123 SFO→JFK')
  })

  it('returns a null description when only the boilerplate is present', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-only-boiler',
          summary: 'Flight',
          description:
            'To see detailed information for automatically created events like this one, use the official Google Calendar app. https://g.co/calendar',
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    if (event.kind !== 'row') return
    expect(event.detail.description).toBeNull()
  })

  it('collapses an unknown attendee responseStatus to unknown', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-att',
          summary: 'Sync',
          attendees: [
            { email: 'a@example.com', responseStatus: 'accepted' },
            { email: 'b@example.com', responseStatus: 'weird-value' },
            { email: 'c@example.com' },
          ],
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    if (event.kind !== 'row') return
    expect(event.detail.attendees.map((a) => a.responseStatus)).toEqual([
      'accepted',
      'unknown',
      'unknown',
    ])
  })

  it('falls back to a null htmlLink when Google omits it', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'evt-5',
          summary: 'No link',
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    if (event.kind !== 'row') return
    expect(event.detail.htmlLink).toBeNull()
  })

  it('still filters cancelled and declined events after enrichment', () => {
    const events = normalizeGoogleCalendarEvents(
      [
        {
          id: 'cancelled',
          status: 'cancelled',
          summary: 'Cancelled',
          start: { date: '2026-06-15' },
          end: { date: '2026-06-16' },
        },
        {
          id: 'declined',
          summary: 'Declined',
          start: { dateTime: '2026-06-17T14:00:00' },
          end: { dateTime: '2026-06-17T15:00:00' },
          attendees: [{ self: true, responseStatus: 'declined' }],
        },
        {
          id: 'kept',
          summary: 'Kept',
          start: { dateTime: '2026-06-17T09:00:00' },
          end: { dateTime: '2026-06-17T10:00:00' },
        },
      ],
      PRIMARY_COLOR,
    )

    expect(events.map((e) => e.id)).toEqual(['kept'])
  })
})

describe('assembleCalendarEvents', () => {
  it('merges events from all successful calendars', () => {
    const result = assembleCalendarEvents([
      { calendarId: 'work', events: [makeBar({ id: 'w1', date: JUNE_17 })] },
      { calendarId: 'family', events: [makeBar({ id: 'f1', date: JUNE_17 })] },
    ])

    expect(result.events.map((e) => e.id)).toEqual(['w1', 'f1'])
    expect(result.failedCalendarCount).toBe(0)
    expect(result.totalCalendarCount).toBe(2)
  })

  it('counts a failed calendar while keeping the successful calendars events', () => {
    const result = assembleCalendarEvents([
      { calendarId: 'work', events: [makeBar({ id: 'w1', date: JUNE_17 })] },
      { calendarId: 'broken', failed: true },
    ])

    expect(result.events.map((e) => e.id)).toEqual(['w1'])
    expect(result.failedCalendarCount).toBe(1)
    expect(result.totalCalendarCount).toBe(2)
  })

  it('reports a total failure when every calendar failed', () => {
    const result = assembleCalendarEvents([
      { calendarId: 'a', failed: true },
      { calendarId: 'b', failed: true },
    ])

    expect(result.events).toEqual([])
    expect(result.failedCalendarCount).toBe(2)
    expect(result.totalCalendarCount).toBe(2)
  })

  it('collapses an event appearing in two calendars to one, first calendar winning', () => {
    const result = assembleCalendarEvents([
      { calendarId: 'work', events: [makeBar({ id: 'shared', date: JUNE_17, color: '#work' })] },
      { calendarId: 'family', events: [makeBar({ id: 'shared', date: JUNE_17, color: '#family' })] },
    ])

    expect(result.events).toHaveLength(1)
    expect(result.events[0].color).toBe('#work')
  })
})

describe('normalizeGoogleCalendarEvents color resolution', () => {
  it('uses an explicit Google event color in preference to the calendar color', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'e1',
          summary: 'Sync',
          colorId: '11',
          start: { dateTime: '2026-06-17T09:00:00' },
          end: { dateTime: '2026-06-17T10:00:00' },
        },
      ],
      '#calendar-color',
      { '11': { background: '#event-color' } },
    )

    expect(event.color).toBe('#event-color')
  })

  it('falls back to the calendar color when no explicit event color is set', () => {
    const [event] = normalizeGoogleCalendarEvents(
      [
        {
          id: 'e1',
          summary: 'Sync',
          start: { dateTime: '2026-06-17T09:00:00' },
          end: { dateTime: '2026-06-17T10:00:00' },
        },
      ],
      '#calendar-color',
      {},
    )

    expect(event.color).toBe('#calendar-color')
  })
})

describe('fetchCalendarList', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
  })

  it('throws UnauthorizedError on a 401 response', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 401,
        json: async () => ({}),
      }),
    )

    await expect(fetchCalendarList('token')).rejects.toBeInstanceOf(
      UnauthorizedError,
    )
  })
})

describe('fetchSourceCalendarEvents', () => {
  it('fetches and merges events from every calendar, colored by its own calendar', async () => {
    const work = { id: 'work@x', summary: 'Work', backgroundColor: '#ff0000', primary: false }
    const family = { id: 'family@x', summary: 'Family', backgroundColor: '#00ff00', primary: true }
    const fetchCalendarEvents = vi.fn(async (_token: string, calendarId: string) => {
      if (calendarId === 'work@x') {
        return [{ id: 'w1', summary: 'Standup', start: { dateTime: '2026-06-17T09:00:00' }, end: { dateTime: '2026-06-17T09:30:00' } }]
      }
      return [{ id: 'f1', summary: 'Dinner', start: { dateTime: '2026-06-17T18:00:00' }, end: { dateTime: '2026-06-17T19:00:00' } }]
    })
    const fetchColors = vi.fn(async () => ({ event: {} }))

    const result = await fetchSourceCalendarEvents(
      'token',
      [work, family],
      RANGE,
      { fetchCalendarEvents, fetchColors },
    )

    expect(result.totalCalendarCount).toBe(2)
    expect(result.failedCalendarCount).toBe(0)
    expect(result.events.map((e) => e.id).sort()).toEqual(['f1', 'w1'])
    expect(result.events.find((e) => e.id === 'w1')?.color).toBe('#ff0000')
    expect(result.events.find((e) => e.id === 'f1')?.color).toBe('#00ff00')
  })

  it('counts a failed calendar without dropping the successful calendars events', async () => {
    const ok = { id: 'ok', summary: 'OK', backgroundColor: '#000000', primary: true }
    const bad = { id: 'bad', summary: 'Bad', backgroundColor: '#111111', primary: false }
    const fetchCalendarEvents = vi.fn(async (_token: string, id: string) => {
      if (id === 'bad') throw new Error('boom')
      return [{ id: 'e1', summary: 'Kept', start: { dateTime: '2026-06-17T09:00:00' }, end: { dateTime: '2026-06-17T10:00:00' } }]
    })

    const result = await fetchSourceCalendarEvents('token', [ok, bad], RANGE, {
      fetchCalendarEvents,
      fetchColors: async () => ({ event: {} }),
    })

    expect(result.failedCalendarCount).toBe(1)
    expect(result.totalCalendarCount).toBe(2)
    expect(result.events.map((e) => e.id)).toEqual(['e1'])
  })

  it('returns an empty result for no calendars', async () => {
    const result = await fetchSourceCalendarEvents('token', [], RANGE, {
      fetchColors: async () => ({ event: {} }),
    })

    expect(result).toEqual({ events: [], failedCalendarCount: 0, totalCalendarCount: 0 })
  })

  it('re-throws an UnauthorizedError (401) from a calendar fetch so it can be retried', async () => {
    const ok = { id: 'ok', summary: 'OK', backgroundColor: '#000000', primary: true }
    const bad = { id: 'bad', summary: 'Bad', backgroundColor: '#111111', primary: false }
    const fetchCalendarEvents = vi.fn(async (_token: string, id: string) => {
      if (id === 'bad') throw new UnauthorizedError()
      return []
    })

    await expect(
      fetchSourceCalendarEvents('token', [ok, bad], RANGE, {
        fetchCalendarEvents,
        fetchColors: async () => ({ event: {} }),
      }),
    ).rejects.toBeInstanceOf(UnauthorizedError)
  })
})
