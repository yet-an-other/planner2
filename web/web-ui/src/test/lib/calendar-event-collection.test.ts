import { describe, expect, it } from 'vitest'
import { replaceCalendarEventRange } from '@/lib/calendar-event-collection'
import type { FetchCalendarEventsResult } from '@/lib/google-calendar-events'
import { makeBar } from './calendar-events.factory'

const june = new Date(2026, 5, 1)
const july = new Date(2026, 6, 1)
const range = { start: june, end: new Date(2026, 5, 30) }

function result(
  outcomes: NonNullable<FetchCalendarEventsResult['outcomes']>,
): FetchCalendarEventsResult {
  const events = outcomes.flatMap((outcome) =>
    'failed' in outcome ? [] : outcome.events,
  )
  return {
    events,
    outcomes,
    failedCalendarCount: outcomes.filter((outcome) => 'failed' in outcome).length,
    totalCalendarCount: outcomes.length,
  }
}

describe('replaceCalendarEventRange', () => {
  it('applies additions, edits, and deletions only inside the refreshed range', () => {
    const existing = [
      makeBar({ id: 'edited', title: 'Old', date: june }),
      makeBar({ id: 'deleted', date: new Date(2026, 5, 2) }),
      makeBar({ id: 'outside', date: july }),
    ]
    const refreshed = result([{ calendarId: 'primary', events: [
      makeBar({ id: 'edited', title: 'New', date: june }),
      makeBar({ id: 'added', date: new Date(2026, 5, 3) }),
    ] }])

    const next = replaceCalendarEventRange(existing, refreshed, range, ['primary'])

    expect(next.map((event) => event.id)).toEqual(['outside', 'edited', 'added'])
    expect(next.find((event) => event.id === 'edited')?.title).toBe('New')
  })

  it('retains failed Source Calendars while replacing successful ones', () => {
    const existing = [
      makeBar({ id: 'work-old', sourceCalendarId: 'work', date: june }),
      makeBar({ id: 'family-old', sourceCalendarId: 'family', date: june }),
    ]
    const refreshed = result([
      { calendarId: 'work', events: [
        makeBar({ id: 'work-new', sourceCalendarId: 'work', date: june }),
      ] },
      { calendarId: 'family', failed: true },
    ])

    const next = replaceCalendarEventRange(existing, refreshed, range, ['work', 'family'])

    expect(next.map((event) => event.id)).toEqual(['family-old', 'work-new'])
  })

  it('replaces multiday events that intersect a range boundary', () => {
    const spanning = makeBar({
      id: 'trip',
      date: new Date(2026, 4, 30),
      endDate: new Date(2026, 5, 2),
    })
    const next = replaceCalendarEventRange(
      [spanning],
      result([{ calendarId: 'primary', events: [] }]),
      range,
      ['primary'],
    )
    expect(next).toEqual([])
  })
})
