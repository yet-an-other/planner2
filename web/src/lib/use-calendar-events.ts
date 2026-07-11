import { useCallback, useEffect, useRef, useState } from 'react'
import { addMonths } from './calendar-dates'
import {
  fetchSourceCalendarEvents,
  type CalendarEvent,
  type FetchCalendarEventsResult,
  type SourceCalendar,
} from './google-calendar-events'
import { mergeCalendarEvents } from './merge-calendar-events'
import { replaceCalendarEventRange, type DateRange } from './calendar-event-collection'
import {
  computeScrollTrigger,
  createFetchedWindow,
  extendFetchedWindow,
  FETCHED_WINDOW_SLAB_MONTHS,
  FETCHED_WINDOW_TRIGGER_BUFFER_MONTHS,
  type CalendarRangeBounds,
  type FetchedWindow,
  type FetchedWindowDirection,
  type VisibleDateRange,
} from './fetched-window'
import type {
  GoogleAccountConnectionState,
  HeaderStatus,
} from './use-google-account-connection'
import {
  loadSavedBusyBlocks,
  persistSavedBusyBlocks,
} from './saved-busy-blocks'

export type FetchCalendarEvents = (
  accessToken: string,
  calendars: SourceCalendar[],
  range: { start: Date; end: Date },
) => Promise<FetchCalendarEventsResult>

export type CalendarEvents = {
  events: CalendarEvent[]
  status: HeaderStatus | null
  maybeFetchMore: (visibleRange: VisibleDateRange) => void
  /** Silently revalidate visible dates plus the shared one-month buffer. */
  refresh: (
    visibleRange: VisibleDateRange,
    selectionOverride?: SourceCalendar[],
  ) => void
  /** Immediately invalidate in-flight work before explicit disconnect. */
  cancel: () => void
}

const LOADING_STATUS: HeaderStatus = { message: 'Loading events…', tone: 'info' }
const LOAD_FAILED_STATUS: HeaderStatus = {
  message: 'Calendar events could not be loaded',
  tone: 'error',
}
const REFRESH_FAILED_STATUS: HeaderStatus = {
  message: 'Calendar events could not be refreshed',
  tone: 'error',
}
const SOME_CALENDARS_LOAD_FAILED_STATUS: HeaderStatus = {
  message: 'Some calendars could not be loaded',
  tone: 'warning',
}
const SOME_CALENDARS_REFRESH_FAILED_STATUS: HeaderStatus = {
  message: 'Some calendars could not be refreshed',
  tone: 'warning',
}

type UseCalendarEventsParams = {
  connection: GoogleAccountConnectionState
  today: Date
  range: CalendarRangeBounds
  selection: SourceCalendar[]
  fetchEvents?: FetchCalendarEvents
}

/**
 * Owns the Fetched Window and all Calendar Event fetch orchestration. Initial
 * loads, slab extension, and bounded stale-while-revalidate refresh share one
 * canonical event collection and reject results from obsolete generations.
 */
export function useCalendarEvents({
  connection,
  today,
  range,
  selection,
  fetchEvents = fetchSourceCalendarEvents,
}: UseCalendarEventsParams): CalendarEvents {
  const [events, setEvents] = useState<CalendarEvent[]>(() =>
    connection.status === 'disconnected' ? loadSavedBusyBlocks() : [],
  )
  const eventsRef = useRef(events)
  const [eventsStatus, setEventsStatus] = useState<HeaderStatus | null>(null)
  const cancelledRef = useRef(false)
  const mountedRef = useRef(true)
  const fetchedWindowRef = useRef<FetchedWindow | null>(null)
  const freshRangesRef = useRef<DateRange[]>([])
  const [pendingFetchCount, setPendingFetchCount] = useState(0)
  const blockingFetchCountRef = useRef(0)
  const refreshInFlightRef = useRef(false)
  const refreshOwnerRef = useRef<string | null>(null)
  const queuedRefreshRef = useRef<{
    visibleRange: VisibleDateRange
    calendars: SourceCalendar[]
  } | null>(null)
  const executeRefreshRef = useRef<(
    visibleRange: VisibleDateRange,
    calendars: SourceCalendar[],
  ) => void>(() => undefined)
  const queuedScrollRangeRef = useRef<VisibleDateRange | null>(null)
  const maybeFetchMoreRef = useRef<(visibleRange: VisibleDateRange) => void>(
    () => undefined,
  )

  const selectionKey = selection.map((calendar) => calendar.id).sort().join('\n')
  const identity =
    connection.status === 'connected'
      ? `${connection.profile.email}\n${selectionKey}`
      : 'disconnected'
  const identityRef = useRef(identity)
  const connectionRef = useRef(connection)
  const selectionRef = useRef(selection)
  const [previousIdentity, setPreviousIdentity] = useState(identity)

  useEffect(() => () => {
    mountedRef.current = false
    cancelledRef.current = true
  }, [])

  useEffect(() => {
    identityRef.current = identity
    connectionRef.current = connection
    selectionRef.current = selection
    eventsRef.current = events
  }, [identity, connection, selection, events])

  useEffect(() => {
    cancelledRef.current = false
    refreshInFlightRef.current = false
    refreshOwnerRef.current = null
    queuedRefreshRef.current = null
    queuedScrollRangeRef.current = null
    blockingFetchCountRef.current = 0
    fetchedWindowRef.current = null
    freshRangesRef.current = []
  }, [identity])

  const applyEvents = useCallback((next: CalendarEvent[], persist: boolean) => {
    if (!mountedRef.current || cancelledRef.current) return
    eventsRef.current = next
    setEvents(next)
    if (persist) persistSavedBusyBlocks(next)
  }, [])

  if (previousIdentity !== identity) {
    setPreviousIdentity(identity)
    setEventsStatus(null)
    setPendingFetchCount(0)
    setEvents(connection.status === 'disconnected' ? loadSavedBusyBlocks() : [])
  }

  useEffect(() => {
    if (connection.status !== 'connected' || selection.length === 0) return

    const expectedIdentity = identity
    const earliest = addMonths(today, -6)
    const latest = addMonths(today, 6)
    const fetchRange = { start: earliest, end: latest }
    fetchedWindowRef.current = createFetchedWindow(earliest, latest)
    freshRangesRef.current = [fetchRange]
    blockingFetchCountRef.current += 1

    fetchEvents(connection.accessToken, selection, fetchRange)
      .then((result) => {
        if (cancelledRef.current || expectedIdentity !== identityRef.current) return
        applyEvents(result.events, true)
        setEventsStatus(statusForResult(result, false))
      })
      .catch(() => {
        if (!cancelledRef.current && expectedIdentity === identityRef.current) {
          setEventsStatus(LOAD_FAILED_STATUS)
        }
      })
      .finally(() => {
        if (cancelledRef.current || expectedIdentity !== identityRef.current) return
        blockingFetchCountRef.current = Math.max(0, blockingFetchCountRef.current - 1)
        drainQueuedWork(
          queuedRefreshRef,
          executeRefreshRef,
          queuedScrollRangeRef,
          maybeFetchMoreRef,
        )
      })
  // The content key deliberately prevents calendar-list metadata refetches from
  // triggering a new ±6-month initial load.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identity, today, fetchEvents, applyEvents])

  const executeRefresh = useCallback(
    (visibleRange: VisibleDateRange, calendars: SourceCalendar[]) => {
      const currentConnection = connectionRef.current
      if (
        cancelledRef.current ||
        currentConnection.status !== 'connected' ||
        calendars.length === 0
      ) return
      if (refreshInFlightRef.current || blockingFetchCountRef.current > 0) {
        queuedRefreshRef.current = { visibleRange, calendars }
        return
      }

      const refreshRange = bufferedRange(visibleRange, range)
      const expectedIdentity = identityRef.current
      refreshInFlightRef.current = true
      refreshOwnerRef.current = expectedIdentity

      fetchEvents(currentConnection.accessToken, calendars, refreshRange)
        .then((result) => {
          if (cancelledRef.current || expectedIdentity !== identityRef.current) return
          const next = replaceCalendarEventRange(
            eventsRef.current,
            result,
            refreshRange,
            calendars.map((calendar) => calendar.id),
          )
          applyEvents(next, true)
          // A foreground refresh intentionally makes previously fetched distant
          // ranges stale; approached slabs add their own disjoint fresh ranges.
          freshRangesRef.current = [refreshRange]
          setEventsStatus(statusForResult(result, true))
        })
        .catch(() => {
          if (!cancelledRef.current && expectedIdentity === identityRef.current) {
            setEventsStatus(REFRESH_FAILED_STATUS)
          }
        })
        .finally(() => {
          if (refreshOwnerRef.current !== expectedIdentity) return
          refreshInFlightRef.current = false
          refreshOwnerRef.current = null
          if (cancelledRef.current || expectedIdentity !== identityRef.current) return
          drainQueuedWork(
            queuedRefreshRef,
            executeRefreshRef,
            queuedScrollRangeRef,
            maybeFetchMoreRef,
          )
        })
    },
    [applyEvents, fetchEvents, range],
  )
  useEffect(() => {
    executeRefreshRef.current = executeRefresh
  }, [executeRefresh])

  const refresh = useCallback(
    (visibleRange: VisibleDateRange, selectionOverride?: SourceCalendar[]) => {
      executeRefresh(visibleRange, selectionOverride ?? selectionRef.current)
    },
    [executeRefresh],
  )

  const fetchSlab = useCallback(
    (accessToken: string, fetchedWindow: FetchedWindow, slab: SlabDirection) => {
      if (refreshInFlightRef.current) return
      const extended = extendFetchedWindow(
        fetchedWindow,
        slab.direction,
        FETCHED_WINDOW_SLAB_MONTHS,
        range,
      )
      if (!slab.advanced(extended, fetchedWindow)) return

      const slabRange = slab.fetchRange(extended, fetchedWindow)
      const expectedIdentity = identityRef.current
      const calendars = selectionRef.current
      fetchedWindowRef.current = extended
      blockingFetchCountRef.current += 1
      setPendingFetchCount((count) => count + 1)

      fetchEvents(accessToken, calendars, slabRange)
        .then((result) => {
          if (cancelledRef.current || expectedIdentity !== identityRef.current) return
          if (isTotalFailure(result)) {
            const current = fetchedWindowRef.current
            if (current && slab.edge(current).getTime() === slab.edge(extended).getTime()) {
              fetchedWindowRef.current = slab.rollback(current, fetchedWindow)
            }
            setEventsStatus(LOAD_FAILED_STATUS)
            return
          }
          const next = mergeCalendarEvents(eventsRef.current, result.events)
          applyEvents(next, true)
          freshRangesRef.current = addFreshRange(freshRangesRef.current, slabRange)
          setEventsStatus(statusForResult(result, false))
        })
        .catch(() => {
          if (cancelledRef.current || expectedIdentity !== identityRef.current) return
          const current = fetchedWindowRef.current
          if (current && slab.edge(current).getTime() === slab.edge(extended).getTime()) {
            fetchedWindowRef.current = slab.rollback(current, fetchedWindow)
          }
          setEventsStatus(LOAD_FAILED_STATUS)
        })
        .finally(() => {
          if (!cancelledRef.current && expectedIdentity === identityRef.current) {
            blockingFetchCountRef.current = Math.max(0, blockingFetchCountRef.current - 1)
            setPendingFetchCount((count) => Math.max(0, count - 1))
            drainQueuedWork(
              queuedRefreshRef,
              executeRefreshRef,
              queuedScrollRangeRef,
              maybeFetchMoreRef,
            )
          }
        })
    },
    [applyEvents, fetchEvents, range],
  )

  const maybeFetchMore = useCallback(
    (visibleRange: VisibleDateRange) => {
      const currentConnection = connectionRef.current
      if (cancelledRef.current || currentConnection.status !== 'connected') return
      if (refreshInFlightRef.current || blockingFetchCountRef.current > 0) {
        queuedScrollRangeRef.current = visibleRange
        return
      }
      const fetchedWindow = fetchedWindowRef.current
      if (!fetchedWindow) return

      const trigger = computeScrollTrigger(
        visibleRange,
        fetchedWindow,
        undefined,
        range,
      )
      if (trigger === 'fetch-future') {
        fetchSlab(currentConnection.accessToken, fetchedWindow, FUTURE_SLAB)
      } else if (trigger === 'fetch-past') {
        fetchSlab(currentConnection.accessToken, fetchedWindow, PAST_SLAB)
      } else if (!freshRangesRef.current.some((fresh) => rangeContains(fresh, visibleRange))) {
        refresh(visibleRange)
      }
    },
    [fetchSlab, range, refresh],
  )

  useEffect(() => {
    maybeFetchMoreRef.current = maybeFetchMore
  }, [maybeFetchMore])

  const cancel = useCallback(() => {
    cancelledRef.current = true
    refreshInFlightRef.current = false
    refreshOwnerRef.current = null
    queuedRefreshRef.current = null
    queuedScrollRangeRef.current = null
  }, [])

  return {
    events,
    status: pendingFetchCount > 0 ? LOADING_STATUS : eventsStatus,
    maybeFetchMore,
    refresh,
    cancel,
  }
}

function bufferedRange(
  visible: VisibleDateRange,
  bounds: CalendarRangeBounds,
): DateRange {
  const start = addMonths(visible.start, -FETCHED_WINDOW_TRIGGER_BUFFER_MONTHS)
  const end = addMonths(visible.end, FETCHED_WINDOW_TRIGGER_BUFFER_MONTHS)
  return {
    start: start < bounds.start ? bounds.start : start,
    end: end > bounds.end ? bounds.end : end,
  }
}

function rangeContains(range: DateRange, visible: VisibleDateRange): boolean {
  return range.start <= visible.start && range.end >= visible.end
}

function addFreshRange(ranges: DateRange[], next: DateRange): DateRange[] {
  const overlapping = ranges.filter(
    (range) => range.start <= next.end && range.end >= next.start,
  )
  if (overlapping.length === 0) return [...ranges, next]
  const start = overlapping.reduce(
    (earliest, range) => (range.start < earliest ? range.start : earliest),
    next.start,
  )
  const end = overlapping.reduce(
    (latest, range) => (range.end > latest ? range.end : latest),
    next.end,
  )
  return [
    ...ranges.filter((range) => !overlapping.includes(range)),
    { start, end },
  ]
}

function drainQueuedWork(
  queuedRefreshRef: React.RefObject<{
    visibleRange: VisibleDateRange
    calendars: SourceCalendar[]
  } | null>,
  executeRefreshRef: React.RefObject<(
    visibleRange: VisibleDateRange,
    calendars: SourceCalendar[],
  ) => void>,
  queuedScrollRef: React.RefObject<VisibleDateRange | null>,
  maybeFetchMoreRef: React.RefObject<(visibleRange: VisibleDateRange) => void>,
): void {
  const queuedRefresh = queuedRefreshRef.current
  queuedRefreshRef.current = null
  if (queuedRefresh) {
    executeRefreshRef.current(
      queuedRefresh.visibleRange,
      queuedRefresh.calendars,
    )
  }
  const queuedScroll = queuedScrollRef.current
  queuedScrollRef.current = null
  if (queuedScroll) maybeFetchMoreRef.current(queuedScroll)
}

function isTotalFailure(result: FetchCalendarEventsResult): boolean {
  return result.totalCalendarCount > 0 && result.failedCalendarCount === result.totalCalendarCount
}

function statusForResult(
  result: FetchCalendarEventsResult,
  refreshing: boolean,
): HeaderStatus | null {
  if (isTotalFailure(result)) return refreshing ? REFRESH_FAILED_STATUS : LOAD_FAILED_STATUS
  if (result.failedCalendarCount > 0) {
    return refreshing
      ? SOME_CALENDARS_REFRESH_FAILED_STATUS
      : SOME_CALENDARS_LOAD_FAILED_STATUS
  }
  return null
}

type SlabDirection = {
  direction: FetchedWindowDirection
  edge: (window: FetchedWindow) => Date
  advanced: (extended: FetchedWindow, original: FetchedWindow) => boolean
  fetchRange: (extended: FetchedWindow, original: FetchedWindow) => DateRange
  rollback: (current: FetchedWindow, original: FetchedWindow) => FetchedWindow
}

const FUTURE_SLAB: SlabDirection = {
  direction: 'future',
  edge: (window) => window.latest,
  advanced: (extended, original) => extended.latest > original.latest,
  fetchRange: (extended, original) => ({ start: original.latest, end: extended.latest }),
  rollback: (current, original) => ({ ...current, latest: original.latest }),
}

const PAST_SLAB: SlabDirection = {
  direction: 'past',
  edge: (window) => window.earliest,
  advanced: (extended, original) => extended.earliest < original.earliest,
  fetchRange: (extended, original) => ({ start: extended.earliest, end: original.earliest }),
  rollback: (current, original) => ({ ...current, earliest: original.earliest }),
}
