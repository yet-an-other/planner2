import { addMonths } from './calendar-dates'

export type FetchedWindow = {
  /** The earliest date that has been fetched from Google Calendar. */
  earliest: Date
  /** The latest date that has been fetched from Google Calendar. */
  latest: Date
}

export type FetchedWindowDirection = 'past' | 'future'

export type ScrollTriggerResult = 'fetch-future' | 'fetch-past' | 'no-op'

export type VisibleDateRange = {
  start: Date
  end: Date
}

/** Slab size in months for each scroll-driven fetch. */
export const FETCHED_WINDOW_SLAB_MONTHS = 3

/** How close the visible range may get to a Fetched Window edge before fetching. */
export const FETCHED_WINDOW_TRIGGER_BUFFER_MONTHS = 1

export function createFetchedWindow(earliest: Date, latest: Date): FetchedWindow {
  return { earliest, latest }
}

/**
 * Extend a Fetched Window by the given number of months in the chosen direction.
 * Returns a new window; the input is not mutated.
 */
export function extendFetchedWindow(
  fetchedWindow: FetchedWindow,
  direction: FetchedWindowDirection,
  months: number,
): FetchedWindow {
  if (direction === 'future') {
    return {
      ...fetchedWindow,
      latest: addMonths(fetchedWindow.latest, months),
    }
  }

  return {
    ...fetchedWindow,
    earliest: addMonths(fetchedWindow.earliest, -months),
  }
}

/**
 * Decide whether the visible range of the Calendar Surface has approached a
 * Fetched Window edge closely enough to trigger another slab fetch.
 *
 * Returns `fetch-future` when the future-most visible date is within the buffer
 * of the window's latest edge, `fetch-past` when the past-most visible date is
 * within the buffer of the earliest edge, otherwise `no-op`.
 */
export function computeScrollTrigger(
  visibleRange: VisibleDateRange,
  fetchedWindow: FetchedWindow,
  bufferMonths = FETCHED_WINDOW_TRIGGER_BUFFER_MONTHS,
): ScrollTriggerResult {
  const futureBoundary = addMonths(fetchedWindow.latest, -bufferMonths)
  if (visibleRange.end.getTime() >= futureBoundary.getTime()) {
    return 'fetch-future'
  }

  const pastBoundary = addMonths(fetchedWindow.earliest, bufferMonths)
  if (visibleRange.start.getTime() <= pastBoundary.getTime()) {
    return 'fetch-past'
  }

  return 'no-op'
}
