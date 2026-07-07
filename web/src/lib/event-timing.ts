import type { EventTiming } from './google-calendar-events'

const fullDateFormatter = new Intl.DateTimeFormat('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  year: 'numeric',
})

const monthDayYearFormatter = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
})

const timeFormatter = new Intl.DateTimeFormat('en-US', {
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
})

/**
 * Renders an `EventTiming` into a single human-readable line for the Event
 * Detail Popover. Pure and locale-pinned (en-US) so it is trivially unit-testable.
 */
export function formatEventTiming(timing: EventTiming): string {
  const { start, end, isAllDay, isMultiday } = timing

  if (isAllDay && !isMultiday) {
    return `All day · ${fullDateFormatter.format(start)}`
  }

  if (isAllDay && isMultiday) {
    return `All day · ${monthDayYearFormatter.format(start)} – ${monthDayYearFormatter.format(end)}`
  }

  if (!isAllDay && !isMultiday) {
    return `${fullDateFormatter.format(start)} · ${timeFormatter.format(start)} – ${timeFormatter.format(end)}`
  }

  // Timed multiday event: show date + time on both ends.
  return `${monthDayYearFormatter.format(start)}, ${timeFormatter.format(start)} – ${monthDayYearFormatter.format(end)}, ${timeFormatter.format(end)}`
}
