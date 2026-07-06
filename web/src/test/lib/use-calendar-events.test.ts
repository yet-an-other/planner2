import { act, renderHook, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { addMonths, toLocalDate } from '@/lib/calendar-dates'
import type {
  CalendarEvent,
  FetchCalendarEventsResult,
  SourceCalendar,
} from '@/lib/google-calendar-events'
import type { GoogleAccountConnectionState } from '@/lib/use-google-account-connection'
import {
  useCalendarEvents,
  type FetchCalendarEvents,
  type FetchCalendarList,
} from '@/lib/use-calendar-events'
import { makeBar } from './calendar-events.factory'

const today = toLocalDate(new Date(2026, 5, 19))
const range = { start: new Date(2016, 5, 19), end: new Date(2036, 5, 19) }

const connected = (accessToken = 'access-token'): GoogleAccountConnectionState => ({
  status: 'connected',
  accessToken,
  profile: { displayName: 'Ada', initials: 'A', pictureUrl: null },
})

const disconnected: GoogleAccountConnectionState = { status: 'disconnected' }

const primaryCalendars = (): SourceCalendar[] => [
  { id: 'primary', summary: 'Primary', backgroundColor: '#2952a3', primary: true },
]

const bar = (id: string, title: string, date: Date) =>
  makeBar({ id, title, date, endDate: date })

/** A fully-successful result carrying the given events for one calendar. */
const ok = (events: CalendarEvent[]): FetchCalendarEventsResult => ({
  events,
  failedCalendarCount: 0,
  totalCalendarCount: 1,
})

const listFn = () => vi.fn<FetchCalendarList>(async () => primaryCalendars())

describe('useCalendarEvents', () => {
  it('fetches the calendar list then the initial ±6-month window for the primary calendar', async () => {
    const fetchEvents = vi.fn<FetchCalendarEvents>(
      async () => ok([bar('evt-1', 'Team Lunch', today)]),
    )
    const fetchCalendarList = listFn()
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )

    await waitFor(() => expect(result.current.events).toHaveLength(1))
    expect(result.current.events[0].id).toBe('evt-1')

    expect(fetchCalendarList).toHaveBeenCalledTimes(1)
    expect(fetchEvents).toHaveBeenCalledTimes(1)
    const [accessToken, selected, fetchRange] = fetchEvents.mock.calls[0]
    expect(accessToken).toBe('access-token')
    expect(selected.map((c: SourceCalendar) => c.id)).toEqual(['primary'])
    expect(fetchRange.start).toEqual(addMonths(today, -6))
    expect(fetchRange.end).toEqual(addMonths(today, 6))
  })

  it('fetches a future slab when maybeFetchMore is called at the future edge', async () => {
    const fetchEvents = vi
      .fn<FetchCalendarEvents>(async () => ok([]))
      .mockResolvedValueOnce(ok([bar('evt-1', 'Lunch', today)]))
      .mockResolvedValueOnce(ok([bar('evt-2', 'Trip', addMonths(today, 7))]))
    const fetchCalendarList = listFn()
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )
    await waitFor(() => expect(result.current.events).toHaveLength(1))

    // A visible range within the 1-month future trigger zone of the ±6 window.
    act(() => {
      result.current.maybeFetchMore({
        start: addMonths(today, 6),
        end: addMonths(today, 6),
      })
    })

    await waitFor(() => expect(result.current.events).toHaveLength(2))
    expect(result.current.events.map((e) => e.id)).toEqual(['evt-1', 'evt-2'])
    // The slab started at the window's future edge (today + 6 months).
    const [, , slabRange] = fetchEvents.mock.calls[1]
    expect(slabRange.start).toEqual(addMonths(today, 6))
    expect(slabRange.end).toEqual(addMonths(today, 9)) // +3 month slab
  })

  it('shows a loading status while a slab fetch is in flight, then clears it', async () => {
    let resolveSlab!: (value: FetchCalendarEventsResult) => void
    const fetchEvents = vi
      .fn<FetchCalendarEvents>(async () => ok([]))
      .mockResolvedValueOnce(ok([]))
      .mockImplementationOnce(
        () => new Promise<FetchCalendarEventsResult>((r) => (resolveSlab = r)),
      )
    const fetchCalendarList = listFn()
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )
    await waitFor(() => expect(result.current.status).toBe(null))

    act(() => {
      result.current.maybeFetchMore({
        start: addMonths(today, 6),
        end: addMonths(today, 6),
      })
    })

    await waitFor(() =>
      expect(result.current.status).toEqual({
        message: 'Loading events…',
        tone: 'info',
      }),
    )

    await act(async () => {
      resolveSlab(ok([]))
    })
    await waitFor(() => expect(result.current.status).toBe(null))
  })

  it('rolls back the window on a total slab failure so the next maybeFetchMore retries', async () => {
    const fetchEvents = vi
      .fn<FetchCalendarEvents>(async () => ok([]))
      .mockResolvedValueOnce(ok([])) // initial
      .mockResolvedValueOnce({
        // slab total failure → window must roll back
        events: [],
        failedCalendarCount: 1,
        totalCalendarCount: 1,
      })
      .mockResolvedValueOnce(ok([bar('evt-2', 'Trip', addMonths(today, 7))])) // retry
    const fetchCalendarList = listFn()
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )
    await waitFor(() => expect(fetchEvents).toHaveBeenCalledTimes(1))

    act(() => {
      result.current.maybeFetchMore({
        start: addMonths(today, 6),
        end: addMonths(today, 6),
      })
    })
    await waitFor(() => expect(fetchEvents).toHaveBeenCalledTimes(2))

    // The total failure rolled the window back, so retrying the same trigger fires again.
    act(() => {
      result.current.maybeFetchMore({
        start: addMonths(today, 6),
        end: addMonths(today, 6),
      })
    })
    await waitFor(() => expect(result.current.events).toHaveLength(1))
    expect(result.current.events[0].id).toBe('evt-2')
  })

  it('clears events and status when the connection becomes disconnected', async () => {
    const fetchEvents = vi.fn<FetchCalendarEvents>(
      async () => ok([bar('evt-1', 'Lunch', today)]),
    )
    const fetchCalendarList = listFn()
    let connection: GoogleAccountConnectionState = connected()

    const { result, rerender } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )
    await waitFor(() => expect(result.current.events).toHaveLength(1))

    connection = disconnected
    rerender()

    await waitFor(() => {
      expect(result.current.events).toHaveLength(0)
      expect(result.current.status).toBe(null)
    })
  })

  it('shows a non-fatal warning when some calendars fail but others succeed', async () => {
    const fetchEvents = vi.fn<FetchCalendarEvents>(async () => ({
      events: [bar('evt-1', 'Lunch', today)],
      failedCalendarCount: 1,
      totalCalendarCount: 2,
    }))
    const fetchCalendarList = listFn()
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )

    await waitFor(() => expect(result.current.events).toHaveLength(1))
    expect(result.current.status).toEqual({
      message: 'Some calendars could not be loaded',
      tone: 'warning',
    })
  })

  it('shows a hard error when every calendar fails on connect', async () => {
    const fetchEvents = vi.fn<FetchCalendarEvents>(async () => ({
      events: [],
      failedCalendarCount: 1,
      totalCalendarCount: 1,
    }))
    const fetchCalendarList = listFn()
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )

    await waitFor(() =>
      expect(result.current.status).toEqual({
        message: 'Calendar events could not be loaded',
        tone: 'error',
      }),
    )
    expect(result.current.events).toHaveLength(0)
  })

  it('shows a hard error when the calendar list itself fails on connect', async () => {
    const fetchEvents = vi.fn<FetchCalendarEvents>(
      async () => ok([bar('evt-1', 'Lunch', today)]),
    )
    const fetchCalendarList = vi.fn<FetchCalendarList>(async () => {
      throw new Error('list unavailable')
    })
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchCalendarList, fetchEvents }),
    )

    await waitFor(() =>
      expect(result.current.status).toEqual({
        message: 'Calendar events could not be loaded',
        tone: 'error',
      }),
    )
    expect(fetchEvents).not.toHaveBeenCalled()
  })
})
