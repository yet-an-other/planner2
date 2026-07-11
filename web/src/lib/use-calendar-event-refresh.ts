import { useEffect, useRef } from 'react'
import type { VisibleDateRange } from './fetched-window'

export const CALENDAR_EVENT_REFRESH_INTERVAL_MS = 5 * 60 * 1000

type UseCalendarEventRefreshParams = {
  enabled: boolean
  deferred: boolean
  visibleRange: VisibleDateRange
  onRefresh: (visibleRange: VisibleDateRange) => void
}

/**
 * Owns browser lifecycle signals and the visible five-minute refresh cadence.
 * Fetching and event collection remain behind the callback seam.
 */
export function useCalendarEventRefresh({
  enabled,
  deferred,
  visibleRange,
  onRefresh,
}: UseCalendarEventRefreshParams): void {
  const enabledRef = useRef(enabled)
  const deferredRef = useRef(deferred)
  const rangeRef = useRef(visibleRange)
  const callbackRef = useRef(onRefresh)
  const pendingRef = useRef(false)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const scheduleRef = useRef<() => void>(() => undefined)

  useEffect(() => {
    enabledRef.current = enabled
    deferredRef.current = deferred
    rangeRef.current = visibleRange
    callbackRef.current = onRefresh
  }, [enabled, deferred, visibleRange, onRefresh])

  useEffect(() => {
    let disposed = false
    function schedule() {
      if (timerRef.current) clearTimeout(timerRef.current)
      timerRef.current = null
      if (!enabledRef.current || document.visibilityState === 'hidden') return
      timerRef.current = setTimeout(trigger, CALENDAR_EVENT_REFRESH_INTERVAL_MS)
    }

    scheduleRef.current = schedule

    function trigger() {
      if (!enabledRef.current) return
      if (document.visibilityState === 'hidden' || deferredRef.current) {
        pendingRef.current = true
        schedule()
        return
      }
      pendingRef.current = false
      callbackRef.current(rangeRef.current)
      schedule()
    }

    let signalQueued = false
    function signal() {
      if (signalQueued) return
      signalQueued = true
      queueMicrotask(() => {
        signalQueued = false
        if (!disposed) trigger()
      })
    }
    function handleVisibility() {
      if (document.visibilityState === 'visible') signal()
      else schedule()
    }
    function handleFocus() {
      if (document.visibilityState !== 'hidden') signal()
    }
    function handleOnline() {
      if (document.visibilityState !== 'hidden') signal()
    }

    document.addEventListener('visibilitychange', handleVisibility)
    window.addEventListener('focus', handleFocus)
    window.addEventListener('online', handleOnline)
    schedule()
    return () => {
      disposed = true
      scheduleRef.current = () => undefined
      document.removeEventListener('visibilitychange', handleVisibility)
      window.removeEventListener('focus', handleFocus)
      window.removeEventListener('online', handleOnline)
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [enabled])

  useEffect(() => {
    if (!enabled) {
      pendingRef.current = false
      if (timerRef.current) clearTimeout(timerRef.current)
      timerRef.current = null
      return
    }
    if (deferred) {
      pendingRef.current = true
      return
    }
    if (pendingRef.current && document.visibilityState !== 'hidden') {
      pendingRef.current = false
      callbackRef.current(rangeRef.current)
      scheduleRef.current()
    }
  }, [enabled, deferred])
}
