import { describe, expect, it } from 'vitest'
import type { SourceCalendar } from '@/lib/google-calendar-events'
import {
  defaultSelectionIds,
  handleSourceCalendars,
  initialSourceCalendarsState,
  reconcileSelection,
  type SourceCalendarsState,
} from '@/lib/source-calendar-reconciliation'

/**
 * Direct coverage of Source Calendar Reconciliation (Planning glossary)
 * at its own interface: signals in, commands and resolutions out — no
 * React, no storage, no timers.
 */

const primary: SourceCalendar = {
  id: 'primary',
  summary: 'Primary',
  backgroundColor: '#2952a3',
  primary: true,
}
const work: SourceCalendar = {
  id: 'work',
  summary: 'Work',
  backgroundColor: '#ff0000',
  primary: false,
}
const family: SourceCalendar = {
  id: 'family',
  summary: 'Family',
  backgroundColor: '#16a34a',
  primary: false,
}
const calendars = [primary, work, family]

const email = 'ada@example.com'

function connectedState(): SourceCalendarsState {
  const { state } = handleSourceCalendars(initialSourceCalendarsState, {
    type: 'connected',
    email,
    persistedIds: [],
  })
  return state
}

function loadedState(): SourceCalendarsState {
  const connected = connectedState()
  const fetchId = connected.nextFetchId - 1
  const { state } = handleSourceCalendars(connected, {
    type: 'listLoaded',
    fetchId,
    list: calendars,
  })
  return state
}

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

describe('connection', () => {
  it('starts the eager list load on connect', () => {
    const { state, commands } = handleSourceCalendars(
      initialSourceCalendarsState,
      { type: 'connected', email, persistedIds: ['work'] },
    )
    expect(state.isLoadingList).toBe(true)
    expect(commands).toEqual([{ type: 'fetchList', fetchId: 1 }])
  })

  it('applies the reconciled persisted selection when the eager load lands', () => {
    const { state } = handleSourceCalendars(connectedState(), {
      type: 'listLoaded',
      fetchId: 1,
      list: calendars,
    })
    expect(state.isLoadingList).toBe(false)
    expect(state.available).toEqual(calendars)
    expect(state.selectedIds).toEqual(['primary'])
    expect(state.status).toBeNull()
  })

  it('reconciles the persisted selection against the loaded list', () => {
    const { state: connected } = handleSourceCalendars(
      initialSourceCalendarsState,
      { type: 'connected', email, persistedIds: ['family', 'deleted'] },
    )
    const { state } = handleSourceCalendars(connected, {
      type: 'listLoaded',
      fetchId: 1,
      list: calendars,
    })
    expect(state.selectedIds).toEqual(['family'])
  })

  it('reports a failed eager load without wiping state', () => {
    const { state } = handleSourceCalendars(connectedState(), {
      type: 'listFailed',
      fetchId: 1,
    })
    expect(state.isLoadingList).toBe(false)
    expect(state.status?.tone).toBe('error')
  })

  it('clears everything on disconnect', () => {
    const { state } = handleSourceCalendars(loadedState(), {
      type: 'disconnected',
    })
    expect(state.available).toEqual([])
    expect(state.selectedIds).toEqual([])
    expect(state.pickerOpen).toBe(false)
    expect(state.isLoadingList).toBe(false)
    expect(state.status).toBeNull()
  })

  it('ignores a stale fetch completion from before the disconnect', () => {
    const connected = connectedState()
    const { state: disconnected } = handleSourceCalendars(connected, {
      type: 'disconnected',
    })
    const { state, commands, resolutions } = handleSourceCalendars(
      disconnected,
      { type: 'listLoaded', fetchId: 1, list: calendars },
    )
    expect(state.available).toEqual([])
    expect(commands).toEqual([])
    expect(resolutions).toEqual([])
  })
})

describe('picker', () => {
  it('refetches before opening the picker', () => {
    const { state, commands } = handleSourceCalendars(loadedState(), {
      type: 'pickerOpenRequested',
    })
    expect(state.isLoadingList).toBe(true)
    expect(state.pickerOpen).toBe(false)
    expect(commands).toEqual([{ type: 'fetchList', fetchId: 2 }])

    const opened = handleSourceCalendars(state, {
      type: 'listLoaded',
      fetchId: 2,
      list: calendars,
    })
    expect(opened.state.pickerOpen).toBe(true)
    expect(opened.state.isLoadingList).toBe(false)
  })

  it('keeps the picker closed when the refetch fails', () => {
    const { state } = handleSourceCalendars(loadedState(), {
      type: 'pickerOpenRequested',
    })
    const failed = handleSourceCalendars(state, {
      type: 'listFailed',
      fetchId: 2,
    })
    expect(failed.state.pickerOpen).toBe(false)
    expect(failed.state.status?.tone).toBe('error')
  })

  it('does nothing while disconnected', () => {
    const { state, commands } = handleSourceCalendars(
      initialSourceCalendarsState,
      { type: 'pickerOpenRequested' },
    )
    expect(commands).toEqual([])
    expect(state.pickerOpen).toBe(false)
  })
})

describe('selection', () => {
  it('persists a saved selection and closes the picker', () => {
    const opened = handleSourceCalendars(loadedState(), {
      type: 'pickerOpenRequested',
    })
    const { state, commands } = handleSourceCalendars(opened.state, {
      type: 'selectionSaved',
      ids: ['work', 'family'],
    })
    expect(state.selectedIds).toEqual(['work', 'family'])
    expect(state.pickerOpen).toBe(false)
    expect(commands).toEqual([
      { type: 'persistSelection', email, ids: ['work', 'family'] },
    ])
  })

  it('never persists an empty selection', () => {
    const { state, commands } = handleSourceCalendars(loadedState(), {
      type: 'selectionSaved',
      ids: [],
    })
    expect(state.selectedIds).toEqual(['primary'])
    expect(commands).toEqual([])
  })
})

describe('reconciliation', () => {
  it('reconciles the committed selection and resolves every caller', () => {
    const started = handleSourceCalendars(loadedState(), {
      type: 'reconcileRequested',
      id: 1,
    })
    expect(started.commands).toEqual([{ type: 'fetchList', fetchId: 2 }])
    expect(started.resolutions).toEqual([])

    const { state, commands, resolutions } = handleSourceCalendars(
      started.state,
      { type: 'listLoaded', fetchId: 2, list: [primary, family] },
    )
    expect(state.selectedIds).toEqual(['primary'])
    expect(state.available).toEqual([primary, family])
    expect(resolutions).toEqual([{ id: 1, calendars: [primary] }])
    expect(commands).toEqual([
      { type: 'persistSelection', email, ids: ['primary'] },
    ])
  })

  it('resolves the last known selection when the fetch fails', () => {
    const saved = handleSourceCalendars(loadedState(), {
      type: 'selectionSaved',
      ids: ['work'],
    })
    const started = handleSourceCalendars(saved.state, {
      type: 'reconcileRequested',
      id: 1,
    })
    const { state, resolutions } = handleSourceCalendars(started.state, {
      type: 'listFailed',
      fetchId: 2,
    })
    expect(resolutions).toEqual([{ id: 1, calendars: [work] }])
    expect(state.selectedIds).toEqual(['work'])
    expect(state.status?.tone).toBe('error')
  })

  it('resolves [] while disconnected', () => {
    const { resolutions } = handleSourceCalendars(
      initialSourceCalendarsState,
      { type: 'reconcileRequested', id: 1 },
    )
    expect(resolutions).toEqual([{ id: 1, calendars: [] }])
  })

  it('serializes runs: one in flight, one shared trailing run', () => {
    const first = handleSourceCalendars(loadedState(), {
      type: 'reconcileRequested',
      id: 1,
    })
    const second = handleSourceCalendars(first.state, {
      type: 'reconcileRequested',
      id: 2,
    })
    expect(second.commands).toEqual([])
    const third = handleSourceCalendars(second.state, {
      type: 'reconcileRequested',
      id: 3,
    })
    expect(third.commands).toEqual([])

    // The completion starts exactly one trailing run, shared by both
    // waiting callers.
    const completed = handleSourceCalendars(third.state, {
      type: 'listLoaded',
      fetchId: 2,
      list: calendars,
    })
    expect(completed.resolutions).toEqual([
      { id: 1, calendars: [primary] },
    ])
    expect(completed.commands).toEqual([
      { type: 'persistSelection', email, ids: ['primary'] },
      { type: 'fetchList', fetchId: 3 },
    ])

    const trailed = handleSourceCalendars(completed.state, {
      type: 'listLoaded',
      fetchId: 3,
      list: calendars,
    })
    expect(trailed.resolutions).toEqual([
      { id: 2, calendars: [primary] },
      { id: 3, calendars: [primary] },
    ])
  })

  it('resolves a stale completion as [] after cancellation', () => {
    const started = handleSourceCalendars(loadedState(), {
      type: 'reconcileRequested',
      id: 1,
    })
    const cancelled = handleSourceCalendars(started.state, {
      type: 'cancelPendingReconciliation',
    })
    const { state, commands, resolutions } = handleSourceCalendars(
      cancelled.state,
      { type: 'listLoaded', fetchId: 2, list: calendars },
    )
    expect(resolutions).toEqual([{ id: 1, calendars: [] }])
    expect(commands).toEqual([])
    // The stale run never applies its result.
    expect(state.selectedIds).toEqual(['primary'])
  })

  it('resolves the queued run stale when the epoch moved', () => {
    const first = handleSourceCalendars(loadedState(), {
      type: 'reconcileRequested',
      id: 1,
    })
    const second = handleSourceCalendars(first.state, {
      type: 'reconcileRequested',
      id: 2,
    })
    const cancelled = handleSourceCalendars(second.state, {
      type: 'cancelPendingReconciliation',
    })
    const completed = handleSourceCalendars(cancelled.state, {
      type: 'listLoaded',
      fetchId: 2,
      list: calendars,
    })
    expect(completed.resolutions).toEqual([
      { id: 1, calendars: [] },
      { id: 2, calendars: [] },
    ])
    expect(completed.commands).toEqual([])
  })

  it('starts fresh work after a cancellation', () => {
    const first = handleSourceCalendars(loadedState(), {
      type: 'reconcileRequested',
      id: 1,
    })
    const cancelled = handleSourceCalendars(first.state, {
      type: 'cancelPendingReconciliation',
    })
    const restarted = handleSourceCalendars(cancelled.state, {
      type: 'reconcileRequested',
      id: 2,
    })
    expect(restarted.commands).toEqual([{ type: 'fetchList', fetchId: 3 }])
  })
})
