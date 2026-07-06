import { useCallback, useEffect, useRef, useState } from 'react'
import { addMonths } from './calendar-dates'
import {
  fetchSourceCalendarEvents,
  type CalendarEvent,
  type FetchCalendarEventsResult,
  type SourceCalendar,
} from './google-calendar-events'
import { mergeCalendarEvents } from './merge-calendar-events'
import {
  computeScrollTrigger,
  createFetchedWindow,
  extendFetchedWindow,
  FETCHED_WINDOW_SLAB_MONTHS,
  type CalendarRangeBounds,
  type FetchedWindow,
  type FetchedWindowDirection,
  type VisibleDateRange,
} from './fetched-window'
import type {
  GoogleAccountConnectionState,
  HeaderStatus,
} from './use-google-account-connection'

/** Fetches Calendar Events for the Selected Source Calendars over a date range. */
export type FetchCalendarEvents = (
  accessToken: string,
  calendars: SourceCalendar[],
  range: { start: Date; end: Date },
) => Promise<FetchCalendarEventsResult>

/** The interface of the Calendar Events module. */
export type CalendarEvents = {
  /** The merged Calendar Events currently available for rendering. */
  events: CalendarEvent[]
  /** Status from the fetch lifecycle: loading, a non-fatal warning, or a load error. */
  status: HeaderStatus | null
  /**
   * Ask the module to fetch another slab if the visible range has approached a
   * Fetched Window edge. No-op when disconnected, inside the window, or already
   * at the Extended Calendar Range boundary.
   */
  maybeFetchMore: (visibleRange: VisibleDateRange) => void
}

const LOADING_STATUS: HeaderStatus = { message: 'Loading events…', tone: 'info' }
const LOAD_FAILED_STATUS: HeaderStatus = {
  message: 'Calendar events could not be loaded',
  tone: 'error',
}
const SOME_CALENDARS_FAILED_STATUS: HeaderStatus = {
  message: 'Some calendars could not be loaded',
  tone: 'warning',
}

type UseCalendarEventsParams = {
  connection: GoogleAccountConnectionState
  today: Date
  range: CalendarRangeBounds
  /** The Selected Source Calendars to fetch Calendar Events from. */
  selection: SourceCalendar[]
  /** Injected so tests can drive fetching without the network or jsdom. */
  fetchEvents?: FetchCalendarEvents
}

/**
 * Owns the Fetched Window and the scroll-driven fetch orchestration that fills
 * it for the current Selected Source Calendars: the initial ±6-month fetch on
 * connect, the per-slab boundary trigger, the optimistic window extension that
 * is rolled back on failure, the by-id dedup merge, and the loading/warning/
 * error status those produce. A change to the selection resets and refetches.
 *
 * The render module computes the visible date range from scroll position (which
 * needs the DOM/virtualizer) and hands it to `maybeFetchMore`. Everything else —
 * the Fetched Window bookkeeping, rollback, and counter — stays behind this seam.
 */
export function useCalendarEvents({
  connection,
  today,
  range,
  selection,
  fetchEvents = fetchSourceCalendarEvents,
}: UseCalendarEventsParams): CalendarEvents {
  const [events, setEvents] = useState<CalendarEvent[]>([])
  const [eventsStatus, setEventsStatus] = useState<HeaderStatus | null>(null)
  // The Fetched Window is the source of truth for scroll-trigger decisions. It is
  // stored in a ref rather than state because it is not rendered directly and the
  // scroll handler must always read the most recent edges synchronously.
  const fetchedWindowRef = useRef<FetchedWindow | null>(null)
  const [pendingFetchCount, setPendingFetchCount] = useState(0)
  // The effect and slab fetches key on the selection's content (ids) rather than
  // the array reference, so a calendar-list refetch that yields the same set of
  // calendars (e.g. reopening the picker) does not spuriously reload events.
  const selectionKey = selection.map((c) => c.id).sort().join('\n')

  // Reset fetched events when the connection transitions to disconnected. Done
  // during render (the React "adjust state when a prop changes" pattern) rather
  // than in an effect, so it does not cascade an extra render.
  const [prevStatus, setPrevStatus] = useState(connection.status)
  if (connection.status !== prevStatus) {
    setPrevStatus(connection.status)
    if (connection.status === 'disconnected') {
      setEvents([])
      setEventsStatus(null)
    }
  }

  useEffect(() => {
    if (connection.status !== 'connected' || selection.length === 0) {
      // Nothing to fetch. Events and status are cleared on disconnect by the
      // render-time adjustment above; while connected with an empty selection
      // (e.g. the list is still loading) there is simply nothing to show yet.
      fetchedWindowRef.current = null
      return
    }

    const accessToken = connection.accessToken
    const earliest = addMonths(today, -6)
    const latest = addMonths(today, 6)
    const fetchRange = { start: earliest, end: latest }

    fetchedWindowRef.current = createFetchedWindow(earliest, latest)

    fetchEvents(accessToken, selection, fetchRange)
      .then((result) => {
        setEvents(result.events)
        setEventsStatus(statusForResult(result))
      })
      .catch(() => setEventsStatus(LOAD_FAILED_STATUS))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [connection, today, selectionKey, fetchEvents])

  const fetchSlab = useCallback(
    (accessToken: string, fetchedWindow: FetchedWindow, slab: SlabDirection) => {
      const extended = extendFetchedWindow(
        fetchedWindow,
        slab.direction,
        FETCHED_WINDOW_SLAB_MONTHS,
        { start: range.start, end: range.end },
      )

      // The module clamps the new edge to the Extended Calendar Range, so a no-op
      // move means the window has already reached that edge.
      if (!slab.advanced(extended, fetchedWindow)) {
        return
      }

      const slabRange = slab.fetchRange(extended, fetchedWindow)
      // Optimistically extend the Fetched Window so repeated calls in the same
      // trigger zone do not fire the same slab twice. Rolled back on failure.
      fetchedWindowRef.current = extended
      setPendingFetchCount((count) => count + 1)

      fetchEvents(accessToken, selection, slabRange)
        .then((result) => {
          if (isTotalFailure(result)) {
            // Total slab failure: roll the window back so the next scroll retries.
            const current = fetchedWindowRef.current
            if (
              current &&
              slab.edge(current).getTime() === slab.edge(extended).getTime()
            ) {
              fetchedWindowRef.current = slab.rollback(current, fetchedWindow)
            }
            setEventsStatus(LOAD_FAILED_STATUS)
            return
          }

          setEvents((previous) => mergeCalendarEvents(previous, result.events))
          setEventsStatus(
            result.failedCalendarCount > 0
              ? SOME_CALENDARS_FAILED_STATUS
              : null,
          )
        })
        .catch(() => {
          // Defensive: per-calendar failures are absorbed inside the fetch, so a
          // rejection here means something unexpected (e.g. a thrown bug). Roll
          // back like a total failure so a later success can recover.
          const current = fetchedWindowRef.current
          if (
            current &&
            slab.edge(current).getTime() === slab.edge(extended).getTime()
          ) {
            fetchedWindowRef.current = slab.rollback(current, fetchedWindow)
          }
        })
        .finally(() => {
          setPendingFetchCount((count) => count - 1)
        })
    },
    [range.start, range.end, selection, fetchEvents],
  )

  const maybeFetchMore = useCallback(
    (visibleRange: VisibleDateRange) => {
      if (connection.status !== 'connected') {
        return
      }

      const fetchedWindow = fetchedWindowRef.current
      if (!fetchedWindow) {
        return
      }

      const trigger = computeScrollTrigger(visibleRange, fetchedWindow, undefined, {
        start: range.start,
        end: range.end,
      })
      if (trigger === 'fetch-future') {
        fetchSlab(connection.accessToken, fetchedWindow, FUTURE_SLAB)
      } else if (trigger === 'fetch-past') {
        fetchSlab(connection.accessToken, fetchedWindow, PAST_SLAB)
      }
    },
    [connection, fetchSlab, range.start, range.end],
  )

  const status = pendingFetchCount > 0 ? LOADING_STATUS : eventsStatus

  return { events, status, maybeFetchMore }
}

/** A total failure is every requested calendar failing; it is a hard error. */
function isTotalFailure(result: FetchCalendarEventsResult): boolean {
  return (
    result.totalCalendarCount > 0 &&
    result.failedCalendarCount === result.totalCalendarCount
  )
}

/** Maps a fetch result to the Header Status it should surface. */
function statusForResult(result: FetchCalendarEventsResult): HeaderStatus | null {
  if (isTotalFailure(result)) {
    return LOAD_FAILED_STATUS
  }
  if (result.failedCalendarCount > 0) {
    return SOME_CALENDARS_FAILED_STATUS
  }
  return null
}

/**
 * Describes one direction of Fetched Window growth as a small set of pure edge
 * operations. Captures everything that differs between past and future slab
 * fetches so the fetch algorithm can be written once, branchlessly.
 */
type SlabDirection = {
  direction: FetchedWindowDirection
  /** The window edge this direction moves (latest for future, earliest for past). */
  edge: (window: FetchedWindow) => Date
  /** True when the extended window actually advanced past the original edge. */
  advanced: (extended: FetchedWindow, original: FetchedWindow) => boolean
  /** Fetch range spanning from the original edge to the extended edge. */
  fetchRange: (
    extended: FetchedWindow,
    original: FetchedWindow,
  ) => { start: Date; end: Date }
  /** Restore this direction's edge after a failed fetch, leaving the other edge. */
  rollback: (current: FetchedWindow, original: FetchedWindow) => FetchedWindow
}

const FUTURE_SLAB: SlabDirection = {
  direction: 'future',
  edge: (window) => window.latest,
  advanced: (extended, original) =>
    extended.latest.getTime() > original.latest.getTime(),
  fetchRange: (extended, original) => ({
    start: original.latest,
    end: extended.latest,
  }),
  rollback: (current, original) => ({ ...current, latest: original.latest }),
}

const PAST_SLAB: SlabDirection = {
  direction: 'past',
  edge: (window) => window.earliest,
  advanced: (extended, original) =>
    extended.earliest.getTime() < original.earliest.getTime(),
  fetchRange: (extended, original) => ({
    start: extended.earliest,
    end: original.earliest,
  }),
  rollback: (current, original) => ({ ...current, earliest: original.earliest }),
}
