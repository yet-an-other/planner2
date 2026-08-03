import { act, renderHook } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { CalendarEvent } from '@/lib/google-calendar-events'
import { useSeparateLayerOverlays } from '@/lib/use-separate-layer-overlays'

/**
 * Direct coverage of the Separate-Layer Overlay contract (Web Experience
 * glossary): structural mutual exclusivity (web ADR 0004) and the two
 * overlays' own payload rules — the Event Detail Popover reconciles
 * against refreshed events and closes on disconnect (ADR 0002), the Day
 * Events Popover updates and stays open through disconnect (ADR 0004).
 * The shared dismiss machinery (scroll, outside-click, focus return) is
 * covered end-to-end by the Calendar Surface suite.
 */

function makeEvent(id: string, title = 'Event'): CalendarEvent {
  return {
    id,
    sourceCalendarId: 'primary',
    title,
    color: '#039BE5',
    kind: 'row',
    date: new Date('2026-07-21T00:00:00'),
    startTime: '9:00 AM',
    durationMinutes: 60,
    timing: {
      start: new Date('2026-07-21T09:00:00'),
      end: new Date('2026-07-21T10:00:00'),
      isAllDay: false,
      isMultiday: false,
    },
    detail: {
      htmlLink: null,
      location: null,
      description: null,
      attendees: [],
    },
  }
}

function makeTrigger(): HTMLButtonElement {
  const trigger = document.createElement('button')
  document.body.appendChild(trigger)
  return trigger
}

function renderOverlays({
  isConnected = true,
  events,
}: { isConnected?: boolean; events?: CalendarEvent[] } = {}) {
  const scrollContainer = document.createElement('div')
  document.body.appendChild(scrollContainer)
  return renderHook(
    ({ connected, nextEvents }) =>
      useSeparateLayerOverlays({
        scrollContainerRef: { current: scrollContainer },
        isConnected: connected,
        events: nextEvents,
      }),
    {
      initialProps: { connected: isConnected, nextEvents: events },
    },
  )
}

describe('mutual exclusivity (ADR 0004)', () => {
  it('opening the detail popover closes an open day list', () => {
    const { result } = renderOverlays()
    act(() => {
      result.current.openDayListFor(
        [makeEvent('a')],
        new Date('2026-07-21T00:00:00'),
        makeTrigger(),
      )
    })
    expect(result.current.dayList.dayEvents).not.toBeNull()

    act(() => {
      result.current.openDetailFor(makeEvent('b'), makeTrigger())
    })
    expect(result.current.detail.event?.id).toBe('b')
    expect(result.current.dayList.dayEvents).toBeNull()
    expect(result.current.dayList.date).toBeNull()
    expect(result.current.dayList.anchorRect).toBeNull()
  })

  it('opening the day list closes an open detail popover', () => {
    const { result } = renderOverlays()
    act(() => {
      result.current.openDetailFor(makeEvent('a'), makeTrigger())
    })
    expect(result.current.detail.event).not.toBeNull()

    act(() => {
      result.current.openDayListFor(
        [makeEvent('b')],
        new Date('2026-07-21T00:00:00'),
        makeTrigger(),
      )
    })
    expect(result.current.dayList.dayEvents).toHaveLength(1)
    expect(result.current.detail.event).toBeNull()
    expect(result.current.detail.anchorRect).toBeNull()
  })
})

describe('Event Detail Popover payload rules (ADR 0002)', () => {
  it('reconciles an open detail against refreshed events', () => {
    const original = makeEvent('a', 'Original')
    const { result, rerender } = renderOverlays({ events: [original] })
    act(() => {
      result.current.openDetailFor(original, makeTrigger())
    })

    const edited = makeEvent('a', 'Edited')
    rerender({ connected: true, nextEvents: [edited] })
    expect(result.current.detail.event?.title).toBe('Edited')

    rerender({ connected: true, nextEvents: [] })
    expect(result.current.detail.event).toBeNull()
  })

  it('closes on Disconnect on This Device', () => {
    const { result, rerender } = renderOverlays()
    act(() => {
      result.current.openDetailFor(makeEvent('a'), makeTrigger())
    })
    rerender({ connected: false, nextEvents: undefined })
    expect(result.current.detail.event).toBeNull()
    expect(result.current.detail.anchorRect).toBeNull()
  })
})

describe('Day Events Popover payload rules (ADR 0004)', () => {
  it('updates the open list after a refresh', () => {
    const { result } = renderOverlays()
    act(() => {
      result.current.openDayListFor(
        [makeEvent('a')],
        new Date('2026-07-21T00:00:00'),
        makeTrigger(),
      )
    })
    act(() => {
      result.current.updateDayList([makeEvent('a'), makeEvent('b')])
    })
    expect(result.current.dayList.dayEvents).toHaveLength(2)
  })

  it('stays open through Disconnect on This Device', () => {
    const { result, rerender } = renderOverlays()
    act(() => {
      result.current.openDayListFor(
        [makeEvent('a')],
        new Date('2026-07-21T00:00:00'),
        makeTrigger(),
      )
    })
    rerender({ connected: false, nextEvents: undefined })
    expect(result.current.dayList.dayEvents).not.toBeNull()
    expect(result.current.dayList.date).not.toBeNull()
  })
})

describe('dismiss guards', () => {
  it('closing an already-closed overlay is a no-op that steals no focus', () => {
    const { result } = renderOverlays()
    const elsewhere = makeTrigger()
    elsewhere.focus()
    act(() => {
      result.current.closeDetail()
      result.current.closeDayList()
    })
    expect(document.activeElement).toBe(elsewhere)
  })

  it('returns focus to the trigger on close', () => {
    const { result } = renderOverlays()
    const trigger = makeTrigger()
    act(() => {
      result.current.openDetailFor(makeEvent('a'), trigger)
    })
    act(() => {
      result.current.closeDetail()
    })
    expect(document.activeElement).toBe(trigger)
  })
})
