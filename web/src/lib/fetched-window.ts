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

/** The bounds of the Extended Calendar Range; passed in to clamp window growth. */
export type CalendarRangeBounds = {
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
 * Returns a new window; the input is not mutated. When a calendar range is
 * supplied, the new edge is clamped to it so the window never extends past the
 * Extended Calendar Range.
 */
export function extendFetchedWindow(
  fetchedWindow: FetchedWindow,
  direction: FetchedWindowDirection,
  months: number,
  calendarRange?: CalendarRangeBounds,
): FetchedWindow {
  if (direction === 'future') {
    const candidate = addMonths(fetchedWindow.latest, months)
    const latest =
      calendarRange && candidate.getTime() > calendarRange.end.getTime()
        ? calendarRange.end
        : candidate
    return {
      ...fetchedWindow,
      latest,
    }
  }

  const candidate = addMonths(fetchedWindow.earliest, -months)
  const earliest =
    calendarRange && candidate.getTime() < calendarRange.start.getTime()
      ? calendarRange.start
      : candidate
  return {
    ...fetchedWindow,
    earliest,
  }
}

/**
 * Decide whether the visible range of the Calendar Surface has approached a
 * Fetched Window edge closely enough to trigger another slab fetch.
 *
 * Returns `fetch-future` when the future-most visible date is within the buffer
 * of the window's latest edge, `fetch-past` when the past-most visible date is
 * within the buffer of the earliest edge, otherwise `no-op`.
 *
 * When a calendar range is supplied, a direction whose Fetched Window edge has
 * already reached the corresponding calendar range boundary returns `no-op`,
 * so no fetch is attempted beyond the Extended Calendar Range.
 */
export function computeScrollTrigger(
  visibleRange: VisibleDateRange,
  fetchedWindow: FetchedWindow,
  bufferMonths = FETCHED_WINDOW_TRIGGER_BUFFER_MONTHS,
  calendarRange?: CalendarRangeBounds,
): ScrollTriggerResult {
  if (visibleRange.end.getTime() >= addMonths(fetchedWindow.latest, -bufferMonths).getTime()) {
    const futureExhausted =
      !!calendarRange &&
      fetchedWindow.latest.getTime() >= calendarRange.end.getTime()
    return futureExhausted ? 'no-op' : 'fetch-future'
  }

  if (visibleRange.start.getTime() <= addMonths(fetchedWindow.earliest, bufferMonths).getTime()) {
    const pastExhausted =
      !!calendarRange &&
      fetchedWindow.earliest.getTime() <= calendarRange.start.getTime()
    return pastExhausted ? 'no-op' : 'fetch-past'
  }

  return 'no-op'
}
