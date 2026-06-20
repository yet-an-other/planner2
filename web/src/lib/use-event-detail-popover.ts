import { useCallback, useState } from 'react'
import type { CalendarEvent } from './google-calendar-events'

/** State and actions for the Event Detail Popover, owned by the Calendar Surface. */
export type EventDetailPopoverController = {
  /** The Calendar Event currently shown in the popover, or null when closed. */
  selectedEvent: CalendarEvent | null
  /** Trigger rect captured at open time; drives the popover's fixed placement. */
  anchorRect: DOMRect | null
  /** Summon the popover for an event, anchored to the element that triggered it. */
  open: (event: CalendarEvent, trigger: HTMLElement) => void
  /** Dismiss the popover. */
  close: () => void
}

/**
 * Owns the Event Detail Popover lifecycle: which event is selected, the anchor
 * rect captured at open time, and the single-cardinality rule (opening a second
 * event replaces the first).
 *
 * Slice 1 of PRD #003. Slice 3 adds close-on-surface-scroll and
 * close-on-disconnect, which need the surface scroll container ref and the
 * connection status and therefore belong here, not in the presentational
 * popover.
 */
export function useEventDetailPopover(): EventDetailPopoverController {
  const [selectedEvent, setSelectedEvent] = useState<CalendarEvent | null>(null)
  const [anchorRect, setAnchorRect] = useState<DOMRect | null>(null)

  const open = useCallback((event: CalendarEvent, trigger: HTMLElement) => {
    setSelectedEvent(event)
    setAnchorRect(trigger.getBoundingClientRect())
  }, [])

  const close = useCallback(() => {
    setSelectedEvent(null)
    setAnchorRect(null)
  }, [])

  return { selectedEvent, anchorRect, open, close }
}
