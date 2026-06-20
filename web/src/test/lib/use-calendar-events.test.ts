import { act, renderHook, waitFor } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { addMonths, toLocalDate } from '@/lib/calendar-dates'
import type { CalendarEvent } from '@/lib/google-calendar-events'
import type { GoogleAccountConnectionState } from '@/lib/use-google-account-connection'
import { useCalendarEvents } from '@/lib/use-calendar-events'
import { makeBar } from './calendar-events.factory'

const today = toLocalDate(new Date(2026, 5, 19))
const range = { start: new Date(2016, 5, 19), end: new Date(2036, 5, 19) }

const connected = (accessToken = 'access-token'): GoogleAccountConnectionState => ({
  status: 'connected',
  accessToken,
  profile: { displayName: 'Ada', initials: 'A', pictureUrl: null },
})

const disconnected: GoogleAccountConnectionState = { status: 'disconnected' }

const bar = (id: string, title: string, date: Date) =>
  makeBar({ id, title, date, endDate: date })

describe('useCalendarEvents', () => {
  it('fetches the initial ±6-month window on connect and exposes the events', async () => {
    const fetchEvents = vi
      .fn<(accessToken: string, range: { start: Date; end: Date }) => Promise<CalendarEvent[]>>()
      .mockResolvedValue([bar('evt-1', 'Team Lunch', today)])
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchEvents }),
    )

    await waitFor(() => expect(result.current.events).toHaveLength(1))

    expect(result.current.events[0].id).toBe('evt-1')
    expect(fetchEvents).toHaveBeenCalledTimes(1)
    const [accessToken, fetchRange] = fetchEvents.mock.calls[0]
    expect(accessToken).toBe('access-token')
    expect(fetchRange.start).toEqual(addMonths(today, -6))
    expect(fetchRange.end).toEqual(addMonths(today, 6))
  })

  it('fetches a future slab when maybeFetchMore is called at the future edge', async () => {
    const initial = [bar('evt-1', 'Lunch', today)]
    const futureEvent = bar('evt-2', 'Trip', addMonths(today, 7))
    const fetchEvents = vi
      .fn<(accessToken: string, range: { start: Date; end: Date }) => Promise<CalendarEvent[]>>()
      .mockResolvedValueOnce(initial)
      .mockResolvedValueOnce([futureEvent])
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchEvents }),
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
    const [, slabRange] = fetchEvents.mock.calls[1]
    expect(slabRange.start).toEqual(addMonths(today, 6))
    expect(slabRange.end).toEqual(addMonths(today, 9)) // +3 month slab
  })

  it('shows a loading status while a slab fetch is in flight, then clears it', async () => {
    let resolveSlab!: (events: CalendarEvent[]) => void
    const fetchEvents = vi
      .fn<(accessToken: string, range: { start: Date; end: Date }) => Promise<CalendarEvent[]>>()
      .mockResolvedValueOnce([])
      .mockImplementationOnce(
        () => new Promise<CalendarEvent[]>((r) => (resolveSlab = r)),
      )
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchEvents }),
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
      resolveSlab([])
    })
    await waitFor(() => expect(result.current.status).toBe(null))
  })

  it('rolls back the window on slab failure so the next maybeFetchMore retries', async () => {
    const fetchEvents = vi
      .fn<(accessToken: string, range: { start: Date; end: Date }) => Promise<CalendarEvent[]>>()
      .mockResolvedValueOnce([])
      .mockRejectedValueOnce(new Error('Network error'))
      .mockResolvedValueOnce([bar('evt-2', 'Trip', addMonths(today, 7))])
    const connection = connected()

    const { result } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchEvents }),
    )
    await waitFor(() => expect(fetchEvents).toHaveBeenCalledTimes(1))

    act(() => {
      result.current.maybeFetchMore({
        start: addMonths(today, 6),
        end: addMonths(today, 6),
      })
    })
    // Failure rolls back the window; status clears once the rejection settles.
    await waitFor(() => expect(result.current.status).toBe(null))

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
    const fetchEvents = vi
      .fn<(accessToken: string, range: { start: Date; end: Date }) => Promise<CalendarEvent[]>>()
      .mockResolvedValue([bar('evt-1', 'Lunch', today)])
    let connection: GoogleAccountConnectionState = connected()

    const { result, rerender } = renderHook(() =>
      useCalendarEvents({ connection, today, range, fetchEvents }),
    )
    await waitFor(() => expect(result.current.events).toHaveLength(1))

    connection = disconnected
    rerender()

    await waitFor(() => {
      expect(result.current.events).toHaveLength(0)
      expect(result.current.status).toBe(null)
    })
  })
})
