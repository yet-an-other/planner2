import { describe, expect, it } from 'vitest'
import type { EventTiming } from '@/lib/google-calendar-events'
import { formatEventTiming } from '@/lib/event-timing'

const allDay = (overrides: Partial<EventTiming> = {}): EventTiming => ({
  start: new Date(2026, 5, 19),
  end: new Date(2026, 5, 19),
  isAllDay: true,
  isMultiday: false,
  ...overrides,
})

describe('formatEventTiming', () => {
  it('formats a single all-day event as "All day" plus the full date', () => {
    expect(formatEventTiming(allDay())).toBe('All day · Fri, Jun 19, 2026')
  })

  it('formats a multiday all-day event as an inclusive date range', () => {
    expect(
      formatEventTiming(
        allDay({
          start: new Date(2026, 5, 15),
          end: new Date(2026, 5, 17),
          isMultiday: true,
        }),
      ),
    ).toBe('All day · Jun 15, 2026 – Jun 17, 2026')
  })

  it('formats a single timed event with start and end times', () => {
    expect(
      formatEventTiming({
        start: new Date(2026, 5, 19, 14, 0),
        end: new Date(2026, 5, 19, 15, 0),
        isAllDay: false,
        isMultiday: false,
      }),
    ).toBe('Fri, Jun 19, 2026 · 2:00 PM – 3:00 PM')
  })

  it('formats a timed multiday event with dates and times on both ends', () => {
    expect(
      formatEventTiming({
        start: new Date(2026, 5, 19, 23, 0),
        end: new Date(2026, 5, 20, 1, 0),
        isAllDay: false,
        isMultiday: true,
      }),
    ).toBe('Jun 19, 2026, 11:00 PM – Jun 20, 2026, 1:00 AM')
  })
})
