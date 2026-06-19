import { fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  addMonths,
  differenceInCalendarDays,
  getCalendarRange,
  startOfMondayWeek,
  toLocalDate,
} from '@/lib/calendar-dates'
import { CalendarSurface } from './calendar-surface'

describe('Google Account Connection', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', '')
  })

  it('tells the user when Google Account Connection is not configured', () => {
    render(<CalendarSurface />)

    expect(
      screen.getByRole('button', { name: /connect google account/i }),
    ).toBeDisabled()
    expect(screen.getByRole('status')).toHaveTextContent(
      'Google client ID is not configured',
    )
  })

  it('connects a Google Account and displays the real profile', async () => {
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    const user = userEvent.setup()
    stubSuccessfulGoogleConnection()

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))

    expect(await screen.findByText('Ada Lovelace')).toBeInTheDocument()
    expect(screen.getByRole('img', { name: /Ada Lovelace/i })).toHaveAttribute(
      'src',
      'https://example.com/ada.png',
    )
    expect(screen.getByRole('status')).toHaveTextContent(
      'Google account connected',
    )
  })

  it('fetches calendar events after connecting', async () => {
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    const user = userEvent.setup()
    const mockFetch = stubSuccessfulGoogleConnectionWithEvents()

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')

    // Verify calendar API was called
    const calendarCalls = mockFetch.mock.calls.filter((call) => {
      const url = String(call[0])
      return url.includes('calendars/primary/events')
    })
    expect(calendarCalls.length).toBeGreaterThan(0)
  })

  it('disconnects a Google Account by revoking the current access token', async () => {
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    const user = userEvent.setup()
    const { revoke } = stubSuccessfulGoogleConnection()

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')
    await user.click(
      screen.getByRole('button', {
        name: /disconnect google account for ada lovelace/i,
      }),
    )

    expect(revoke).toHaveBeenCalledWith('access-token', expect.any(Function))
    expect(
      screen.getByRole('button', { name: /connect google account/i }),
    ).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent(
      'Google account disconnected',
    )
  })
})

describe('Scroll-driven fetching', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    vi.setSystemTime(new Date(2026, 5, 19))
  })

  it('fetches a future 3-month slab when scrolling into the future trigger zone', async () => {
    const user = userEvent.setup()
    const mockFetch = stubSuccessfulGoogleConnectionWithEvents()
    const today = toLocalDate(new Date(2026, 5, 19))

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')

    // Wait for the initial +/-6 month fetch, then clear the call log.
    await vi.waitFor(() => {
      expect(
        mockFetch.mock.calls.some((call) =>
          String(call[0]).includes('calendars/primary/events'),
        ),
      ).toBe(true)
    })
    mockFetch.mockClear()

    // Scroll so the visible range reaches the future trigger zone (~1 month
    // before the +6-month edge of the Fetched Window).
    const surface = document.querySelector(
      '[aria-label="Calendar Surface"]',
    ) as HTMLElement
    Object.defineProperty(surface, 'clientHeight', {
      configurable: true,
      value: 128,
    })
    const range = getCalendarRange(today)
    const triggerWeekStart = startOfMondayWeek(addMonths(today, 5))
    const triggerWeekIndex =
      differenceInCalendarDays(triggerWeekStart, range.start) / 7
    fireEvent.scroll(surface, { target: { scrollTop: triggerWeekIndex * 128 } })

    // A future slab fetch was fired with a range starting near the +6-month edge.
    // (Merged events then render via the existing overlay path, exercised by the
    // layout-engine tests; driving the virtualizer to a specific week is not
    // feasible in jsdom because it has no viewport size.)
    await vi.waitFor(() => {
      const slabCalls = mockFetch.mock.calls.filter((call) => {
        if (!String(call[0]).includes('calendars/primary/events')) return false
        const timeMin = new URL(String(call[0])).searchParams.get('timeMin')
        if (!timeMin) return false
        return new Date(timeMin) >= addMonths(today, 5)
      })
      expect(slabCalls.length).toBeGreaterThan(0)
    })
  })

  it('fetches a past 3-month slab when scrolling into the past trigger zone', async () => {
    const user = userEvent.setup()
    const mockFetch = stubSuccessfulGoogleConnectionWithEvents()
    const today = toLocalDate(new Date(2026, 5, 19))

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')

    await vi.waitFor(() => {
      expect(
        mockFetch.mock.calls.some((call) =>
          String(call[0]).includes('calendars/primary/events'),
        ),
      ).toBe(true)
    })
    mockFetch.mockClear()

    // Scroll so the visible range reaches the past trigger zone (~1 month
    // after the -6-month edge of the Fetched Window).
    const surface = document.querySelector(
      '[aria-label="Calendar Surface"]',
    ) as HTMLElement
    Object.defineProperty(surface, 'clientHeight', {
      configurable: true,
      value: 128,
    })
    const range = getCalendarRange(today)
    const triggerWeekStart = startOfMondayWeek(addMonths(today, -5))
    const triggerWeekIndex =
      differenceInCalendarDays(triggerWeekStart, range.start) / 7
    fireEvent.scroll(surface, { target: { scrollTop: triggerWeekIndex * 128 } })

    // A past slab fetch was fired with a range ending near the -6-month edge.
    await vi.waitFor(() => {
      const slabCalls = mockFetch.mock.calls.filter((call) => {
        if (!String(call[0]).includes('calendars/primary/events')) return false
        const timeMax = new URL(String(call[0])).searchParams.get('timeMax')
        if (!timeMax) return false
        return new Date(timeMax) <= addMonths(today, -5)
      })
      expect(slabCalls.length).toBeGreaterThan(0)
    })
  })

  it('shows a loading status while a scroll-driven fetch is in flight', async () => {
    const user = userEvent.setup()
    const { mockFetch, resolveSlab } =
      stubSuccessfulGoogleConnectionWithDeferredEvents()
    const today = toLocalDate(new Date(2026, 5, 19))

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')
    await vi.waitFor(() => {
      expect(
        mockFetch.mock.calls.some((call) =>
          String(call[0]).includes('calendars/primary/events'),
        ),
      ).toBe(true)
    })

    const status = screen.getByRole('status')
    const surface = document.querySelector('[aria-label="Calendar Surface"]') as HTMLElement
    Object.defineProperty(surface, 'clientHeight', {
      configurable: true,
      value: 128,
    })
    const range = getCalendarRange(today)
    const triggerWeekStart = startOfMondayWeek(addMonths(today, 5))
    const triggerWeekIndex =
      differenceInCalendarDays(triggerWeekStart, range.start) / 7
    fireEvent.scroll(surface, { target: { scrollTop: triggerWeekIndex * 128 } })

    expect(await within(status).findByText('Loading events…')).toBeInTheDocument()

    resolveSlab([])
    await vi.waitFor(() => {
      expect(screen.getByRole('status')).not.toHaveTextContent('Loading events…')
    })
  })

  it('clears the loading status when a scroll fetch fails and retries on the next scroll', async () => {
    const user = userEvent.setup()
    const { mockFetch, rejectSlab } =
      stubSuccessfulGoogleConnectionWithDeferredEvents()
    const today = toLocalDate(new Date(2026, 5, 19))

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')
    await vi.waitFor(() => {
      expect(
        mockFetch.mock.calls.some((call) =>
          String(call[0]).includes('calendars/primary/events'),
        ),
      ).toBe(true)
    })
    mockFetch.mockClear()

    const { surface, scrollIntoFutureTrigger } =
      mountScrollSurface(today)

    scrollIntoFutureTrigger()
    expect(await screen.findByText('Loading events…')).toBeInTheDocument()

    // The failed slab must not extend the Fetched Window, so the loading
    // status clears and the next scroll into the same zone retries.
    rejectSlab(new Error('Network error'))
    await vi.waitFor(() => {
      expect(screen.getByRole('status')).not.toHaveTextContent('Loading events…')
    })

    mockFetch.mockClear()
    scrollIntoFutureTrigger()

    await vi.waitFor(() => {
      const slabCalls = mockFetch.mock.calls.filter((call) =>
        String(call[0]).includes('calendars/primary/events'),
      )
      expect(slabCalls.length).toBeGreaterThan(0)
    })
    // surface is referenced to keep the helper bound to the right element.
    expect(surface).toBeInTheDocument()
  })
})

describe('Account lifecycle and error recovery', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    vi.setSystemTime(new Date(2026, 5, 19))
  })

  it('clears events on disconnect and performs a fresh initial fetch on reconnect', async () => {
    const user = userEvent.setup()
    const mockFetch = stubSuccessfulGoogleConnectionWithEvents()
    const today = toLocalDate(new Date(2026, 5, 19))

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')
    await vi.waitFor(() => {
      expect(eventsFetchCount(mockFetch)).toBeGreaterThanOrEqual(1)
    })

    // Disconnecting clears the event array and resets the Fetched Window: a
    // subsequent scroll must not fire any slab fetch.
    await user.click(
      screen.getByRole('button', {
        name: /disconnect google account for ada lovelace/i,
      }),
    )
    mockFetch.mockClear()

    const { scrollIntoFutureTrigger } = mountScrollSurface(today)
    scrollIntoFutureTrigger()
    await Promise.resolve()
    expect(eventsFetchCount(mockFetch)).toBe(0)

    // Reconnecting performs a fresh ±6-month initial fetch.
    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await vi.waitFor(() => {
      expect(eventsFetchCount(mockFetch)).toBeGreaterThanOrEqual(1)
    })
  })
})

function eventsFetchCount(mockFetch: { mock: { calls: unknown[][] } }) {
  return mockFetch.mock.calls.filter((call) =>
    String(call[0]).includes('calendars/primary/events'),
  ).length
}

function mountScrollSurface(today: Date) {
  const surface = document.querySelector(
    '[aria-label="Calendar Surface"]',
  ) as HTMLElement
  Object.defineProperty(surface, 'clientHeight', {
    configurable: true,
    value: 128,
  })
  const range = getCalendarRange(today)

  const scrollIntoFutureTrigger = () => {
    const triggerWeekStart = startOfMondayWeek(addMonths(today, 5))
    const triggerWeekIndex =
      differenceInCalendarDays(triggerWeekStart, range.start) / 7
    fireEvent.scroll(surface, { target: { scrollTop: triggerWeekIndex * 128 } })
  }

  return { surface, scrollIntoFutureTrigger }
}

function stubSuccessfulGoogleConnection() {
  const requestAccessToken = vi.fn()
  const revoke = vi.fn((_accessToken: string, done: () => void) => {
    done()
  })
  const initTokenClient = vi.fn(({ callback }) => {
    requestAccessToken.mockImplementation(() => {
      callback({ access_token: 'access-token' })
    })

    return { requestAccessToken }
  })

  vi.stubGlobal('google', {
    accounts: {
      oauth2: {
        initTokenClient,
        revoke,
      },
    },
  })
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        name: 'Ada Lovelace',
        picture: 'https://example.com/ada.png',
      }),
    }),
  )

  return { revoke }
}

function stubSuccessfulGoogleConnectionWithEvents() {
  const requestAccessToken = vi.fn()
  const revoke = vi.fn((_accessToken: string, done: () => void) => {
    done()
  })
  const initTokenClient = vi.fn(({ callback }) => {
    requestAccessToken.mockImplementation(() => {
      callback({ access_token: 'access-token' })
    })

    return { requestAccessToken }
  })

  vi.stubGlobal('google', {
    accounts: {
      oauth2: {
        initTokenClient,
        revoke,
      },
    },
  })

  const mockFetch = vi.fn((input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input.toString()

    if (url.includes('oauth2/v3/userinfo')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          name: 'Ada Lovelace',
          picture: 'https://example.com/ada.png',
        }),
      })
    }

    if (url.includes('calendarList/primary')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          backgroundColor: '#2952a3',
        }),
      })
    }

    if (url.includes('calendar/v3/colors')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          event: {},
        }),
      })
    }

    if (url.includes('calendars/primary/events')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          items: [
            {
              id: 'evt-1',
              summary: 'Team Lunch',
              start: { date: new Date().toISOString().split('T')[0] },
              end: {
                date: new Date(Date.now() + 86_400_000)
                  .toISOString()
                  .split('T')[0],
              },
            },
          ],
        }),
      })
    }

    return Promise.resolve({ ok: false })
  })

  vi.stubGlobal('fetch', mockFetch)

  return mockFetch
}

function stubSuccessfulGoogleConnectionWithDeferredEvents() {
  const requestAccessToken = vi.fn()
  const revoke = vi.fn((_accessToken: string, done: () => void) => {
    done()
  })
  const initTokenClient = vi.fn(({ callback }) => {
    requestAccessToken.mockImplementation(() => {
      callback({ access_token: 'access-token' })
    })

    return { requestAccessToken }
  })

  vi.stubGlobal('google', {
    accounts: {
      oauth2: {
        initTokenClient,
        revoke,
      },
    },
  })

  const pendingSlabResolvers: Array<{
    resolve: (items: unknown[]) => void
    reject: (error: Error) => void
  }> = []

  const mockFetch = vi.fn((input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input.toString()

    if (url.includes('oauth2/v3/userinfo')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          name: 'Ada Lovelace',
          picture: 'https://example.com/ada.png',
        }),
      })
    }

    if (url.includes('calendarList/primary')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({ backgroundColor: '#2952a3' }),
      })
    }

    if (url.includes('calendar/v3/colors')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({ event: {} }),
      })
    }

    if (url.includes('calendars/primary/events')) {
      const timeMin = new URL(url).searchParams.get('timeMin')
      const isFutureSlab =
        !!timeMin && new Date(timeMin) >= addMonths(new Date(2026, 5, 19), 5)

      if (isFutureSlab) {
        // Defer resolution so the loading status and rollback are observable.
        return new Promise((resolve, reject) => {
          pendingSlabResolvers.push({
            resolve: (items) => resolve({ ok: true, json: async () => ({ items }) }),
            reject,
          })
        })
      }

      return Promise.resolve({
        ok: true,
        json: async () => ({ items: [] }),
      })
    }

    return Promise.resolve({ ok: false })
  })

  vi.stubGlobal('fetch', mockFetch)

  const drainPending = () => pendingSlabResolvers.splice(0)

  return {
    mockFetch,
    resolveSlab: (items: unknown[]) => {
      drainPending().forEach(({ resolve }) => resolve(items))
    },
    rejectSlab: (error: Error) => {
      drainPending().forEach(({ reject }) => reject(error))
    },
  }
}
