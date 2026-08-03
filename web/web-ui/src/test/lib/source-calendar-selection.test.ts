import { beforeEach, describe, expect, it } from 'vitest'
import {
  loadPersistedSelection,
  persistSelection,
  sourceCalendarStorageKey,
} from '@/lib/source-calendar-selection'

describe('persisted selection storage', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('round-trips a selection for one account', () => {
    persistSelection('ada@example.com', ['work', 'family'])

    expect(loadPersistedSelection('ada@example.com')).toEqual(['work', 'family'])
  })

  it('keeps two accounts isolated in the same browser', () => {
    persistSelection('ada@example.com', ['work'])
    persistSelection('bob@example.com', ['family'])

    expect(loadPersistedSelection('ada@example.com')).toEqual(['work'])
    expect(loadPersistedSelection('bob@example.com')).toEqual(['family'])
  })

  it('keys each account under its own email', () => {
    expect(sourceCalendarStorageKey('ada@example.com')).toBe(
      'planner.sourceCalendars.ada@example.com',
    )
  })

  it('returns an empty selection when nothing is stored', () => {
    expect(loadPersistedSelection('never@example.com')).toEqual([])
  })

  it('returns an empty selection when the stored value is corrupt', () => {
    localStorage.setItem('planner.sourceCalendars.corrup@example.com', '{not json')
    expect(loadPersistedSelection('corrup@example.com')).toEqual([])
  })
})
