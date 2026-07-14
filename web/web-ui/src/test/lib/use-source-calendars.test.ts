import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { SourceCalendar } from '@/lib/google-calendar-events'
import { sourceCalendarStorageKey } from '@/lib/source-calendar-selection'
import { useSourceCalendars } from '@/lib/use-source-calendars'

const connection = {
  status: 'connected' as const,
  accessToken: 'token',
  profile: {
    email: 'ada@example.com',
    displayName: 'Ada',
    initials: 'A',
    pictureUrl: null,
  },
}
const primary: SourceCalendar = {
  id: 'primary', summary: 'Primary', backgroundColor: '#111', primary: true,
}
const family: SourceCalendar = {
  id: 'family', summary: 'Family', backgroundColor: '#222', primary: false,
}

beforeEach(() => localStorage.clear())

describe('useSourceCalendars reconciliation', () => {
  it('drops unavailable selections, falls back to primary, and persists success', async () => {
    localStorage.setItem(
      sourceCalendarStorageKey(connection.profile.email),
      JSON.stringify(['family']),
    )
    const fetchCalendarList = vi
      .fn()
      .mockResolvedValueOnce([primary, family])
      .mockResolvedValueOnce([primary])
    const { result } = renderHook(() =>
      useSourceCalendars({ connection, fetchCalendarList }),
    )
    await waitFor(() =>
      expect(result.current.selectionCalendars.map((calendar) => calendar.id)).toEqual(['family']),
    )

    let reconciled: SourceCalendar[] = []
    await act(async () => {
      reconciled = await result.current.reconcileCalendars()
    })

    expect(reconciled.map((calendar) => calendar.id)).toEqual(['primary'])
    expect(result.current.selectionCalendars.map((calendar) => calendar.id)).toEqual(['primary'])
    expect(localStorage.getItem(sourceCalendarStorageKey(connection.profile.email)))
      .toBe(JSON.stringify(['primary']))
  })

  it('preserves the active and persisted selection when reconciliation fails', async () => {
    localStorage.setItem(
      sourceCalendarStorageKey(connection.profile.email),
      JSON.stringify(['family']),
    )
    const fetchCalendarList = vi
      .fn()
      .mockResolvedValueOnce([primary, family])
      .mockRejectedValueOnce(new Error('offline'))
    const { result } = renderHook(() =>
      useSourceCalendars({ connection, fetchCalendarList }),
    )
    await waitFor(() => expect(result.current.selectionCalendars).toHaveLength(1))

    let reconciled: SourceCalendar[] = []
    await act(async () => {
      reconciled = await result.current.reconcileCalendars()
    })

    expect(reconciled.map((calendar) => calendar.id)).toEqual(['family'])
    expect(result.current.selectionCalendars.map((calendar) => calendar.id)).toEqual(['family'])
    expect(localStorage.getItem(sourceCalendarStorageKey(connection.profile.email)))
      .toBe(JSON.stringify(['family']))
  })
})
