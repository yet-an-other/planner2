import { beforeEach, describe, expect, it } from 'vitest'
import {
  clearSavedBusyBlocks,
  loadSavedBusyBlocks,
  persistSavedBusyBlocks,
} from '@/lib/saved-busy-blocks'
import { makeRow } from './calendar-events.factory'

beforeEach(() => localStorage.clear())

describe('Saved Busy Blocks', () => {
  it('persists only timing and color without event or source identity', () => {
    persistSavedBusyBlocks([
      makeRow({
        id: 'private-google-id',
        sourceCalendarId: 'work',
        title: 'Secret interview',
        date: new Date(2026, 5, 17, 9),
        color: '#123456',
        detail: {
          description: 'private notes',
          location: 'private place',
          htmlLink: 'https://calendar.google.com/private',
          attendees: [{ email: 'person@example.com', displayName: null, responseStatus: 'accepted' }],
        },
      }),
    ])

    const raw = localStorage.getItem('planner.savedBusyBlocks') ?? ''
    expect(raw).not.toContain('Secret interview')
    expect(raw).not.toContain('private-google-id')
    expect(raw).not.toContain('private notes')
    expect(raw).not.toContain('person@example.com')
    expect(raw).not.toContain('work')
    expect(raw).toContain('#123456')

    const [saved] = loadSavedBusyBlocks()
    expect(saved.title).toBe('Busy')
    expect(saved.sourceCalendarId).toBe('saved')
    expect(saved.detail.description).toBe(null)
  })

  it('clears persisted placeholders explicitly', () => {
    persistSavedBusyBlocks([
      makeRow({ id: 'event', date: new Date(2026, 5, 17, 9) }),
    ])
    clearSavedBusyBlocks()
    expect(loadSavedBusyBlocks()).toEqual([])
  })
})
