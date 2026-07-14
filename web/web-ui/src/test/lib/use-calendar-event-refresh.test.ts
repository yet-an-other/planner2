import { act, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import {
  CALENDAR_EVENT_REFRESH_INTERVAL_MS,
  useCalendarEventRefresh,
} from '@/lib/use-calendar-event-refresh'

const visibleRange = { start: new Date(2026, 5, 1), end: new Date(2026, 5, 7) }

beforeEach(() => {
  vi.useFakeTimers()
  Object.defineProperty(document, 'visibilityState', {
    configurable: true,
    value: 'visible',
  })
})
afterEach(() => vi.useRealTimers())

describe('useCalendarEventRefresh', () => {
  it('refreshes every five visible minutes and coalesces lifecycle signals', async () => {
    const onRefresh = vi.fn()
    renderHook(() => useCalendarEventRefresh({
      enabled: true,
      deferred: false,
      visibleRange,
      onRefresh,
    }))

    act(() => vi.advanceTimersByTime(CALENDAR_EVENT_REFRESH_INTERVAL_MS))
    expect(onRefresh).toHaveBeenCalledTimes(1)

    await act(async () => {
      window.dispatchEvent(new Event('focus'))
      window.dispatchEvent(new Event('online'))
      await Promise.resolve()
    })
    expect(onRefresh).toHaveBeenCalledTimes(2)
  })

  it('pauses while hidden and refreshes immediately when visible again', async () => {
    const onRefresh = vi.fn()
    renderHook(() => useCalendarEventRefresh({
      enabled: true,
      deferred: false,
      visibleRange,
      onRefresh,
    }))
    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'hidden' })
    act(() => document.dispatchEvent(new Event('visibilitychange')))
    act(() => vi.advanceTimersByTime(CALENDAR_EVENT_REFRESH_INTERVAL_MS * 2))
    expect(onRefresh).not.toHaveBeenCalled()

    Object.defineProperty(document, 'visibilityState', { configurable: true, value: 'visible' })
    await act(async () => {
      document.dispatchEvent(new Event('visibilitychange'))
      await Promise.resolve()
    })
    expect(onRefresh).toHaveBeenCalledTimes(1)
  })

  it('coalesces triggers while deferred and refreshes once after deferral', async () => {
    const onRefresh = vi.fn()
    let deferred = true
    const { rerender } = renderHook(() => useCalendarEventRefresh({
      enabled: true,
      deferred,
      visibleRange,
      onRefresh,
    }))
    await act(async () => {
      window.dispatchEvent(new Event('focus'))
      window.dispatchEvent(new Event('online'))
      await Promise.resolve()
    })
    expect(onRefresh).not.toHaveBeenCalled()

    deferred = false
    rerender()
    expect(onRefresh).toHaveBeenCalledTimes(1)
  })
})
