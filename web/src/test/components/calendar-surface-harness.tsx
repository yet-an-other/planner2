import { fireEvent, render, screen } from '@testing-library/react'
import { vi } from 'vitest'
import {
  differenceInCalendarDays,
  getCalendarRange,
  startOfMondayWeek,
  toLocalDate,
} from '@/lib/calendar-dates'
import { CalendarSurface } from '@/components/calendar-surface'

/**
 * Mounts the Calendar Surface with a stubbed connected Google Account and a
 * controllable ResizeObserver, then returns a `revealTodayWeek` helper.
 *
 * jsdom has no layout, so TanStack Virtual renders zero week rows unless the
 * scroll element reports a real size. This harness sizes the surface and
 * scrolls it to the week of Today so the today-week's events actually render.
 *
 * Shared by the Event Detail Popover and Day Events Popover integration tests.
 */
export function mountWithEvents(
  items: Array<Record<string, unknown>>,
  options: { connect?: boolean } = {},
) {
  const { connect = true } = options
  const observers: Array<{ cb: (entries: unknown[]) => void; el: HTMLElement }> = []
  class TestResizeObserver {
    cb: (entries: unknown[]) => void
    constructor(cb: (entries: unknown[]) => void) {
      this.cb = cb
    }
    observe(el: HTMLElement) {
      observers.push({ cb: this.cb, el })
    }
    unobserve() {}
    disconnect() {}
  }
  vi.stubGlobal('ResizeObserver', TestResizeObserver)

  const requestCode = vi.fn()
  const initCodeClient = vi.fn(({ callback }) => {
    requestCode.mockImplementation(() => callback({ code: 'the-code' }))
    return { requestCode }
  })
  vi.stubGlobal('google', { accounts: { oauth2: { initCodeClient, revoke: vi.fn((_accessToken: string, done: () => void) => done()) } } })
  vi.stubGlobal(
    'fetch',
    vi.fn((input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input.toString()
      if (url === '/api/auth/callback')
        return Promise.resolve({ ok: true, json: async () => ({ accessToken: 'access-token', profile: { email: 'ada@example.com', displayName: 'Ada', initials: 'A', pictureUrl: 'x' } }) })
      if (url === '/api/token')
        return Promise.resolve({ ok: false, status: 401, json: async () => ({}) })
      if (url.includes('calendarList'))
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
      if (url.includes('colors'))
        return Promise.resolve({ ok: true, json: async () => ({ event: {} }) })
      if (url.includes('calendars/primary/events'))
        return Promise.resolve({ ok: true, json: async () => ({ items }) })
      return Promise.resolve({ ok: false })
    }),
  )

  const today = toLocalDate(new Date(2026, 5, 19))
  const range = getCalendarRange(today)
  const todayWeekIndex = differenceInCalendarDays(startOfMondayWeek(today), range.start) / 7

  render(<CalendarSurface />)
  if (connect) {
    fireEvent.click(screen.getByRole('button', { name: /connect google/i }))
  }

  // jsdom has no layout: size the scroll element and scroll it to Today's week
  // after the virtualizer has subscribed its ResizeObserver, so the today-week
  // actually renders.
  const revealTodayWeek = () => {
    const surface = document.querySelector(
      '[aria-label="Calendar Surface"]',
    ) as HTMLElement
    Object.defineProperty(surface, 'offsetHeight', { configurable: true, value: 1280 })
    Object.defineProperty(surface, 'offsetWidth', { configurable: true, value: 1024 })
    for (const o of observers) {
      o.cb([{ target: o.el, borderBoxSize: [{ inlineSize: 1024, blockSize: 1280 }] }])
    }
    fireEvent.scroll(surface, { target: { scrollTop: todayWeekIndex * 128 } })
    return surface
  }

  return { revealTodayWeek }
}
