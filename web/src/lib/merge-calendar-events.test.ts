import { describe, expect, it } from 'vitest'
import type { CalendarEvent } from './google-calendar-events'
import { mergeCalendarEvents } from './merge-calendar-events'

const row = (id: string, title: string): CalendarEvent => ({
  kind: 'row',
  id,
  title,
  date: new Date(2026, 5, 19),
  startTime: '09:00',
  durationMinutes: 60,
  color: '#2952a3',
})

const bar = (id: string, title: string): CalendarEvent => ({
  kind: 'bar',
  eventType: 'all-day',
  id,
  title,
  date: new Date(2026, 5, 19),
  endDate: new Date(2026, 5, 19),
  color: '#2952a3',
})

describe('mergeCalendarEvents', () => {
  it('keeps every event when there is no overlap', () => {
    const existing = [row('a', 'Lunch'), row('b', 'Call')]
    const incoming = [row('c', 'Sync'), row('d', 'Demo')]

    const merged = mergeCalendarEvents(existing, incoming)

    expect(merged.map((e) => e.id)).toEqual(['a', 'b', 'c', 'd'])
  })

  it('drops incoming events whose id already exists in the current set', () => {
    const existing = [row('a', 'Lunch'), row('b', 'Call')]
    const incoming = [row('a', 'Lunch again'), row('c', 'Sync')]

    const merged = mergeCalendarEvents(existing, incoming)

    expect(merged.map((e) => e.id)).toEqual(['a', 'b', 'c'])
    // The existing entry is preserved (not overwritten by the incoming duplicate).
    expect(merged.find((e) => e.id === 'a')).toEqual(row('a', 'Lunch'))
  })

  it('treats ids as the only identity, regardless of kind or title', () => {
    // The same Google event id returned by two slabs must collapse to one entry,
    // even if the shape differs between fetches.
    const existing = [bar('shared', 'Trip')]
    const incoming = [row('shared', 'Trip (renamed)')]

    const merged = mergeCalendarEvents(existing, incoming)

    expect(merged.map((e) => e.id)).toEqual(['shared'])
  })

  it('returns the existing set unchanged when incoming is empty', () => {
    const existing = [row('a', 'Lunch')]

    expect(mergeCalendarEvents(existing, [])).toEqual(existing)
  })

  it('returns incoming untouched when existing is empty', () => {
    const incoming = [bar('a', 'Trip'), row('b', 'Sync')]

    expect(mergeCalendarEvents([], incoming)).toEqual(incoming)
  })
})
