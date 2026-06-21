import { describe, expect, it } from 'vitest'
import {
  normalizeGoogleCalendarEvents,
} from '@/lib/google-calendar-events'

const PRIMARY_COLOR = '#2952a3'

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
