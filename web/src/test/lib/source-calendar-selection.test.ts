import { beforeEach, describe, expect, it } from 'vitest'
import type { SourceCalendar } from '@/lib/google-calendar-events'
import {
  defaultSelectionIds,
  loadPersistedSelection,
  persistSelection,
  reconcileSelection,
  sourceCalendarStorageKey,
} from '@/lib/source-calendar-selection'

const calendars: SourceCalendar[] = [
  {
    id: 'primary',
    summary: 'Primary',
    backgroundColor: '#2952a3',
    primary: true,
  },
  { id: 'work', summary: 'Work', backgroundColor: '#ff0000', primary: false },
  { id: 'family', summary: 'Family', backgroundColor: '#16a34a', primary: false },
]

describe('reconcileSelection', () => {
  it('falls back to the primary calendar when nothing is stored', () => {
    expect(reconcileSelection([], calendars)).toEqual(['primary'])
  })

  it('keeps stored ids that are still available', () => {
    expect(reconcileSelection(['work', 'family'], calendars)).toEqual([
      'work',
      'family',
    ])
  })

  it('prunes stored ids that are no longer available', () => {
    expect(reconcileSelection(['work', 'deleted'], calendars)).toEqual(['work'])
  })

  it('falls back to primary when no stored calendar survives', () => {
    expect(reconcileSelection(['gone-1', 'gone-2'], calendars)).toEqual([
      'primary',
    ])
  })

  it('preserves a stored selection that includes the primary calendar', () => {
    expect(reconcileSelection(['work', 'primary'], calendars)).toEqual([
      'work',
      'primary',
    ])
  })
})

describe('defaultSelectionIds', () => {
  it('selects the primary calendar', () => {
    expect(defaultSelectionIds(calendars)).toEqual(['primary'])
  })

  it('falls back to the first calendar when none is primary (minimum-one)', () => {
    const noPrimary = [
      { id: 'a', summary: 'A', backgroundColor: '#000', primary: false },
      { id: 'b', summary: 'B', backgroundColor: '#fff', primary: false },
    ]
    expect(defaultSelectionIds(noPrimary)).toEqual(['a'])
  })
})

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
