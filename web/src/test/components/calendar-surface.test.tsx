import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import {
  addMonths,
  differenceInCalendarDays,
  getCalendarRange,
  startOfMondayWeek,
  toLocalDate,
} from '@/lib/calendar-dates'
import { CalendarSurface } from '@/components/calendar-surface'
import { mountWithEvents } from './calendar-surface-harness'

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

    // Verify the calendar events API was called (it lands after the calendar
    // list resolves and the selection flows into the events module).
    await waitFor(() => {
      const calendarCalls = mockFetch.mock.calls.filter((call) => {
        const url = String(call[0])
        return url.includes('calendars/primary/events')
      })
      expect(calendarCalls.length).toBeGreaterThan(0)
    })
  })

  it('opens the Source Calendar Picker from the header control while connected', async () => {
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    const user = userEvent.setup()
    stubSuccessfulGoogleConnectionWithEvents()

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')

    await user.click(screen.getByRole('button', { name: /choose calendars/i }))

    const dialog = await screen.findByRole('dialog')
    expect(dialog).toHaveTextContent('Calendars')
    // The primary calendar from the stubbed list is listed and selected by default.
    expect(screen.getByRole('checkbox', { name: /primary/i })).toBeChecked()
  })

  it('disconnects a Google Account and returns to the connect state', async () => {
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    const user = userEvent.setup()
    stubSuccessfulGoogleConnection()

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')
    await user.click(
      screen.getByRole('button', {
        name: /disconnect google account for ada lovelace/i,
      }),
    )

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

describe('Event Detail Popover', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    vi.setSystemTime(new Date(2026, 5, 19))
  })

  it('opens the popover with the title and Google Calendar link when a bar is clicked', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        htmlLink: 'https://www.google.com/calendar/event?eid=evt-1',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
    ])

    await screen.findByText('Ada')
    revealTodayWeek()
    const trigger = await screen.findByRole('button', {
      name: /team lunch.*open details/i,
    })
    expect(trigger).toHaveAttribute('aria-expanded', 'false')

    fireEvent.click(trigger)

    const dialog = await screen.findByRole('dialog')
    expect(trigger).toHaveAttribute('aria-expanded', 'true')
    expect(dialog).toHaveTextContent('Team Lunch')
    expect(dialog).toHaveTextContent('All day')
    expect(
      screen.getByRole('link', { name: /open in google calendar/i }),
    ).toHaveAttribute('href', 'https://www.google.com/calendar/event?eid=evt-1')
  })

  it('closes the popover when Escape is pressed', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
    ])

    await screen.findByText('Ada')
    revealTodayWeek()
    await screen.findByText('Team Lunch')
    fireEvent.click(
      await screen.findByRole('button', { name: /team lunch.*open details/i }),
    )
    await screen.findByRole('dialog')

    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' })

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    )
  })

  it('keeps at most one popover open, replacing the previous event', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
      {
        id: 'evt-2',
        summary: 'Sprint Demo',
        start: { date: '2026-06-16' },
        end: { date: '2026-06-17' },
      },
    ])

    await screen.findByText('Ada')
    revealTodayWeek()
    await screen.findByText('Team Lunch')
    fireEvent.click(
      await screen.findByRole('button', { name: /team lunch.*open details/i }),
    )
    expect(await screen.findByRole('dialog')).toHaveTextContent('Team Lunch')

    fireEvent.click(
      screen.getByRole('button', { name: /sprint demo.*open details/i }),
    )

    await waitFor(() =>
      expect(screen.getByRole('dialog')).toHaveTextContent('Sprint Demo'),
    )
    expect(screen.getAllByRole('dialog')).toHaveLength(1)
  })

  it('does not render interactive event triggers when disconnected', async () => {
    mountWithEvents(
      [
        {
          id: 'evt-1',
          summary: 'Team Lunch',
          start: { date: '2026-06-19' },
          end: { date: '2026-06-20' },
        },
      ],
      { connect: false },
    )

    // While disconnected there are no interactive event triggers to summon a popover.
    expect(
      screen.queryByRole('button', { name: /open details/i }),
    ).not.toBeInTheDocument()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('opens the popover when Enter is pressed on a focused trigger', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
    ])
    const user = userEvent.setup()

    await screen.findByText('Ada')
    revealTodayWeek()
    const trigger = await screen.findByRole('button', {
      name: /team lunch.*open details/i,
    })
    trigger.focus()

    await user.keyboard('{Enter}')

    expect(await screen.findByRole('dialog')).toBeInTheDocument()
  })

  it('closes the popover when clicking outside of it', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
    ])

    await screen.findByText('Ada')
    revealTodayWeek()
    fireEvent.click(
      await screen.findByRole('button', { name: /team lunch.*open details/i }),
    )
    await screen.findByRole('dialog')

    fireEvent.mouseDown(document.body)

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    )
  })

  it('closes the popover when the Calendar Surface is scrolled', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
    ])

    await screen.findByText('Ada')
    const surface = revealTodayWeek()
    fireEvent.click(
      await screen.findByRole('button', { name: /team lunch.*open details/i }),
    )
    await screen.findByRole('dialog')

    fireEvent.scroll(surface, { target: { scrollTop: 9999 } })

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    )
  })

  it('closes the popover when the Google Account Connection is disconnected', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
    ])

    await screen.findByText('Ada')
    revealTodayWeek()
    fireEvent.click(
      await screen.findByRole('button', { name: /team lunch.*open details/i }),
    )
    await screen.findByRole('dialog')

    fireEvent.click(
      screen.getByRole('button', {
        name: /disconnect google account for ada/i,
      }),
    )

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    )
  })

  it('moves focus to the close button on open and back to the trigger on close', async () => {
    const { revealTodayWeek } = mountWithEvents([
      {
        id: 'evt-1',
        summary: 'Team Lunch',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
    ])

    await screen.findByText('Ada')
    revealTodayWeek()
    const trigger = await screen.findByRole('button', {
      name: /team lunch.*open details/i,
    })
    fireEvent.click(trigger)
    const dialog = await screen.findByRole('dialog')

    // Focus moves into the popover on open.
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /close/i })).toHaveFocus(),
    )

    fireEvent.keyDown(dialog, { key: 'Escape' })

    // Focus returns to the trigger on close.
    await waitFor(() => expect(trigger).toHaveFocus())
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
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
  const requestCode = vi.fn()
  const revoke = vi.fn((_accessToken: string, done: () => void) => {
    done()
  })
  const initCodeClient = vi.fn(({ callback }) => {
    requestCode.mockImplementation(() => {
      callback({ code: 'the-code' })
    })

    return { requestCode }
  })

  vi.stubGlobal('google', {
    accounts: {
      oauth2: {
        initCodeClient,
        revoke,
      },
    },
  })
  vi.stubGlobal(
    'fetch',
    vi.fn((input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input.toString()
      if (url === '/api/auth/callback')
        return Promise.resolve({
          ok: true,
          json: async () => ({
            accessToken: 'access-token',
            profile: {
              email: 'ada@example.com',
              displayName: 'Ada Lovelace',
              initials: 'AL',
              pictureUrl: 'https://example.com/ada.png',
            },
          }),
        })
      if (url === '/api/token')
        return Promise.resolve({ ok: false, status: 401, json: async () => ({}) })
      return Promise.resolve({ ok: true, json: async () => ({ items: [] }) })
    }),
  )

  return { revoke }
}

function stubSuccessfulGoogleConnectionWithEvents() {
  const requestCode = vi.fn()
  const revoke = vi.fn((_accessToken: string, done: () => void) => {
    done()
  })
  const initCodeClient = vi.fn(({ callback }) => {
    requestCode.mockImplementation(() => {
      callback({ code: 'the-code' })
    })

    return { requestCode }
  })

  vi.stubGlobal('google', {
    accounts: {
      oauth2: {
        initCodeClient,
        revoke,
      },
    },
  })

  const mockFetch = vi.fn((input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input.toString()

    if (url === '/api/auth/callback') {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          accessToken: 'access-token',
          profile: {
            email: 'ada@example.com',
            displayName: 'Ada Lovelace',
            initials: 'AL',
            pictureUrl: 'https://example.com/ada.png',
          },
        }),
      })
    }

    if (url === '/api/token') {
      return Promise.resolve({ ok: false, status: 401, json: async () => ({}) })
    }

    if (url.includes('calendarList')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          items: [
            {
              id: 'primary',
              summary: 'Primary',
              backgroundColor: '#2952a3',
              primary: true,
              accessRole: 'owner',
            },
          ],
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
  const requestCode = vi.fn()
  const revoke = vi.fn((_accessToken: string, done: () => void) => {
    done()
  })
  const initCodeClient = vi.fn(({ callback }) => {
    requestCode.mockImplementation(() => {
      callback({ code: 'the-code' })
    })

    return { requestCode }
  })

  vi.stubGlobal('google', {
    accounts: {
      oauth2: {
        initCodeClient,
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

    if (url === '/api/auth/callback') {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          accessToken: 'access-token',
          profile: {
            email: 'ada@example.com',
            displayName: 'Ada Lovelace',
            initials: 'AL',
            pictureUrl: 'https://example.com/ada.png',
          },
        }),
      })
    }

    if (url === '/api/token') {
      return Promise.resolve({ ok: false, status: 401, json: async () => ({}) })
    }

    if (url.includes('calendarList')) {
      return Promise.resolve({
        ok: true,
        json: async () => ({
          items: [
            {
              id: 'primary',
              summary: 'Primary',
              backgroundColor: '#2952a3',
              primary: true,
              accessRole: 'owner',
            },
          ],
        }),
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

describe('Day Events Popover', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    vi.setSystemTime(new Date(2026, 5, 19))
  })

  // Six timed events on Today (Fri, Jun 19) -> the cell shows 3 + "+3 more".
  function sixTimedEvents() {
    return Array.from({ length: 6 }, (_, i) => ({
      id: `evt-${i}`,
      summary: `Meeting ${i + 1}`,
      start: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:00:00` },
      end: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:30:00` },
    }))
  }

  async function openDayList() {
    const harness = mountWithEvents(sixTimedEvents())
    await screen.findByText('Ada')
    const surface = harness.revealTodayWeek()
    const trigger = await screen.findByRole('button', { name: /\+3 more/i })
    fireEvent.click(trigger)
    const dialog = await screen.findByRole('dialog')
    return { surface, dialog, trigger }
  }

  it('opens the day list with every event when "+N more" is clicked', async () => {
    const { dialog } = await openDayList()

    expect(dialog).toHaveTextContent('Friday, June 19, 2026')
    // All six events are listed, not just the three that fit in the cell.
    for (let i = 1; i <= 6; i++) {
      expect(dialog).toHaveTextContent(`Meeting ${i}`)
    }
  })

  it('closes the day list when Escape is pressed', async () => {
    const { dialog } = await openDayList()

    fireEvent.keyDown(dialog, { key: 'Escape' })

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    )
  })

  it('closes the day list when clicking outside of it', async () => {
    await openDayList()

    fireEvent.mouseDown(document.body)

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    )
  })

  it('closes the day list when the Calendar Surface is scrolled', async () => {
    const { surface } = await openDayList()

    fireEvent.scroll(surface, { target: { scrollTop: 9999 } })

    await waitFor(() =>
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument(),
    )
  })

  it('moves focus to the close button on open and back to the trigger on close', async () => {
    const { trigger } = await openDayList()

    await waitFor(() =>
      expect(screen.getByRole('button', { name: /close/i })).toHaveFocus(),
    )

    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' })

    await waitFor(() => expect(trigger).toHaveFocus())
  })

  it('keeps at most one overlay open: opening the day list closes an open Event Detail Popover', async () => {
    // An all-day bar (clickable for detail) plus enough rows to overflow.
    const events = [
      {
        id: 'bar-1',
        summary: 'All-hands',
        start: { date: '2026-06-19' },
        end: { date: '2026-06-20' },
      },
      ...sixTimedEvents(),
    ]
    const { revealTodayWeek } = mountWithEvents(events)
    await screen.findByText('Ada')
    revealTodayWeek()

    // Open the Event Detail Popover from the bar.
    fireEvent.click(
      await screen.findByRole('button', { name: /all-hands.*open details/i }),
    )
    expect(await screen.findByRole('dialog')).toHaveTextContent('All-hands')

    // Opening the day list replaces it with the day list. (1 bar + 6 rows = 7
    // items -> the overflow reads "+4 more".)
    fireEvent.click(await screen.findByRole('button', { name: /\+4 more/i }))

    await waitFor(() =>
      expect(screen.getByRole('dialog')).toHaveTextContent(
        'Friday, June 19, 2026',
      ),
    )
    expect(screen.getAllByRole('dialog')).toHaveLength(1)
  })

  it('drills into an event: selecting a list item opens its Event Detail Popover and closes the day list', async () => {
    const events = Array.from({ length: 6 }, (_, i) => ({
      id: `evt-${i}`,
      summary: `Meeting ${i + 1}`,
      htmlLink: `https://www.google.com/calendar/event?eid=evt-${i}`,
      start: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:00:00` },
      end: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:30:00` },
    }))
    const { revealTodayWeek } = mountWithEvents(events)
    await screen.findByText('Ada')
    revealTodayWeek()
    fireEvent.click(await screen.findByRole('button', { name: /\+3 more/i }))
    await screen.findByRole('dialog')

    // Select a list item (Meeting 4 is hidden in the cell but present in the list).
    fireEvent.click(
      screen.getByRole('button', { name: /meeting 4.*open details/i }),
    )

    // The day list closes and the Event Detail Popover opens for that event.
    await waitFor(() =>
      expect(screen.getByRole('dialog')).toHaveTextContent('Meeting 4'),
    )
    expect(screen.getAllByRole('dialog')).toHaveLength(1)
    expect(
      screen.getByRole('link', { name: /open in google calendar/i }),
    ).toHaveAttribute('href', 'https://www.google.com/calendar/event?eid=evt-3')
  })

  it('closes the day list when a surface event is keyboard-activated while the list is open', async () => {
    // Enter/Space fire `click`, not the outside-click `mousedown`, so mutual
    // exclusivity must be enforced at the wiring level (not via outside-click).
    const events = Array.from({ length: 6 }, (_, i) => ({
      id: `evt-${i}`,
      summary: `Meeting ${i + 1}`,
      htmlLink: `https://www.google.com/calendar/event?eid=evt-${i}`,
      start: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:00:00` },
      end: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:30:00` },
    }))
    const { revealTodayWeek } = mountWithEvents(events)
    const user = userEvent.setup()
    await screen.findByText('Ada')
    revealTodayWeek()
    fireEvent.click(await screen.findByRole('button', { name: /\+3 more/i }))
    await screen.findByRole('dialog') // day list open

    // Keyboard-activate a visible surface row (scoped to the surface; the day
    // list also renders a Meeting 1 item, but it is portaled outside the surface).
    const surfaceEl = document.querySelector(
      '[aria-label="Calendar Surface"]',
    ) as HTMLElement
    const row = within(surfaceEl).getByRole('button', {
      name: /meeting 1.*open details/i,
    })
    row.focus()
    await user.keyboard('{Enter}')

    // The day list closed and the Event Detail Popover opened (its Google link is
    // unique to the detail popover); exactly one overlay remains.
    await waitFor(() =>
      expect(
        screen.getByRole('link', { name: /open in google calendar/i }),
      ).toBeInTheDocument(),
    )
    expect(screen.getAllByRole('dialog')).toHaveLength(1)
  })

  it('switches the day list to another day when a different cell\'s "+N more" is clicked', async () => {
    // Thursday (Jun 18) and Friday (Jun 19) in the today-week, each overflowing.
    const events = [
      ...Array.from({ length: 6 }, (_, i) => ({
        id: `thu-${i}`,
        summary: `Thu ${i + 1}`,
        start: { dateTime: `2026-06-18T${String(9 + i).padStart(2, '0')}:00:00` },
        end: { dateTime: `2026-06-18T${String(9 + i).padStart(2, '0')}:30:00` },
      })),
      ...Array.from({ length: 6 }, (_, i) => ({
        id: `fri-${i}`,
        summary: `Fri ${i + 1}`,
        start: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:00:00` },
        end: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:30:00` },
      })),
    ]
    const { revealTodayWeek } = mountWithEvents(events)
    await screen.findByText('Ada')
    revealTodayWeek()

    // Thursday's trigger precedes Friday's in DOM order (Mon-first week).
    const triggers = await screen.findAllByRole('button', { name: /\+3 more/i })
    fireEvent.click(triggers[1]) // Friday
    expect(await screen.findByRole('dialog')).toHaveTextContent(
      'Friday, June 19, 2026',
    )

    fireEvent.click(triggers[0]) // Thursday replaces Friday

    await waitFor(() =>
      expect(screen.getByRole('dialog')).toHaveTextContent(
        'Thursday, June 18, 2026',
      ),
    )
    expect(screen.getAllByRole('dialog')).toHaveLength(1)
  })

  it('anchors the drill-through Event Detail Popover to the "+N more" trigger, not the list item', async () => {
    // jsdom has no layout, so getBoundingClientRect is all zeros by default.
    // Stub the "+N more" trigger's rect to a distinctive position; the detail
    // popover must inherit THAT rect (the cell), not the list item's zero rect.
    const events = Array.from({ length: 6 }, (_, i) => ({
      id: `evt-${i}`,
      summary: `Meeting ${i + 1}`,
      htmlLink: `https://www.google.com/calendar/event?eid=evt-${i}`,
      start: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:00:00` },
      end: { dateTime: `2026-06-19T${String(9 + i).padStart(2, '0')}:30:00` },
    }))
    const { revealTodayWeek } = mountWithEvents(events)
    await screen.findByText('Ada')
    revealTodayWeek()

    const moreButton = await screen.findByRole('button', { name: /\+3 more/i })
    Object.defineProperty(moreButton, 'getBoundingClientRect', {
      configurable: true,
      value: () => ({
        top: 200,
        bottom: 220,
        left: 50,
        right: 70,
        height: 20,
        width: 20,
        x: 50,
        y: 200,
        toJSON: () => ({}),
      }),
    })
    fireEvent.click(moreButton)
    await screen.findByRole('dialog') // day list open

    // Drill into Meeting 4 (hidden in the cell, present only in the day list).
    fireEvent.click(
      screen.getByRole('button', { name: /meeting 4.*open details/i }),
    )

    // The Event Detail Popover opened (its Google link is unique to detail) and
    // is anchored to the "+N more" trigger: bottom 220 + gap 8 = top 228.
    const detail = await screen.findByRole('dialog')
    expect(detail).toHaveTextContent('Meeting 4')
    expect(
      screen.getByRole('link', { name: /open in google calendar/i }),
    ).toBeInTheDocument()
    expect(Number.parseInt(detail.style.top, 10)).toBe(228)
  })
})
