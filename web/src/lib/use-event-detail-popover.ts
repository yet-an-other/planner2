import { useCallback, useEffect, useRef, useState } from 'react'
import type { CalendarEvent } from './google-calendar-events'

/** State and actions for the Event Detail Popover, owned by the Calendar Surface. */
export type EventDetailPopoverController = {
  /** The Calendar Event currently shown in the popover, or null when closed. */
  selectedEvent: CalendarEvent | null
  /** Trigger rect captured at open time; drives the popover's fixed placement. */
  anchorRect: DOMRect | null
  /** Ref attached to the popover root so outside-click can tell it apart. */
  popoverRef: React.RefObject<HTMLDivElement | null>
  /** Summon the popover for an event, anchored to the element that triggered it. */
  open: (event: CalendarEvent, trigger: HTMLElement) => void
  /** Dismiss the popover. A no-op (no focus theft) when nothing is open. */
  close: () => void
}

type UseEventDetailPopoverParams = {
  /** Ref to the Calendar Surface scroll container; scrolling it closes the popover. */
  scrollContainerRef: React.RefObject<HTMLElement | null>
  /** Whether the Google Account Connection is currently connected. */
  isConnected: boolean
}

/**
 * Owns the Event Detail Popover lifecycle: which event is selected, the anchor
 * rect captured at open time, the single-cardinality rule, and the dismiss
 * triggers that depend on the surface (close-on-scroll, close-on-disconnect,
 * outside-click). Focus is returned to the opening trigger on any close.
 *
 * The presentational `<EventDetailPopover>` owns focus-on-open (focusing its
 * close button); this hook owns focus-return-on-close uniformly across every
 * dismiss path, including disconnect (where the trigger is gone, so nothing is
 * focused).
 */
export function useEventDetailPopover({
  scrollContainerRef,
  isConnected,
}: UseEventDetailPopoverParams): EventDetailPopoverController {
  const [selectedEvent, setSelectedEvent] = useState<CalendarEvent | null>(null)
  const [anchorRect, setAnchorRect] = useState<DOMRect | null>(null)

  const triggerRef = useRef<HTMLElement | null>(null)
  const popoverRef = useRef<HTMLDivElement | null>(null)
  // Mirror selected state into a ref so listeners can read it without re-binding.
  const selectedEventRef = useRef<CalendarEvent | null>(selectedEvent)
  useEffect(() => {
    selectedEventRef.current = selectedEvent
  }, [selectedEvent])

  const open = useCallback((event: CalendarEvent, trigger: HTMLElement) => {
    triggerRef.current = trigger
    setSelectedEvent(event)
    setAnchorRect(trigger.getBoundingClientRect())
  }, [])

  const close = useCallback(() => {
    if (selectedEventRef.current === null) {
      // Already closed: bail so listeners (scroll, outside-click) never steal focus.
      return
    }
    setSelectedEvent(null)
    setAnchorRect(null)
  }, [])

  // Return focus to the trigger whenever the popover transitions open -> closed,
  // regardless of which dismiss path caused it.
  const prevSelectedRef = useRef<CalendarEvent | null>(selectedEvent)
  useEffect(() => {
    if (prevSelectedRef.current !== null && selectedEvent === null) {
      const trigger = triggerRef.current
      if (trigger && document.contains(trigger)) {
        trigger.focus()
      }
      triggerRef.current = null
    }
    prevSelectedRef.current = selectedEvent
  }, [selectedEvent])

  // Close on disconnect. State is cleared during render (the React "adjust state
  // when a prop changes" pattern); focus return is skipped because the trigger
  // is gone in the disconnected state (handled by the effect's contains check).
  const [prevConnected, setPrevConnected] = useState(isConnected)
  if (prevConnected !== isConnected) {
    setPrevConnected(isConnected)
    if (!isConnected) {
      setSelectedEvent(null)
      setAnchorRect(null)
    }
  }

  // Close when the Calendar Surface is scrolled (the virtualization-correctness
  // rule: a popover anchored to a Week Row that scrolls out of view would float
  // orphaned). Passive; a no-op when already closed.
  useEffect(() => {
    const scrollElement = scrollContainerRef.current
    if (!scrollElement) {
      return
    }
    const handleScroll = () => {
      if (selectedEventRef.current !== null) {
        close()
      }
    }
    scrollElement.addEventListener('scroll', handleScroll, { passive: true })
    return () => scrollElement.removeEventListener('scroll', handleScroll)
  }, [scrollContainerRef, close])

  // Close on outside click. Only attached while open; a click inside the popover
  // (or that re-opens via a trigger) is left to the trigger handlers.
  useEffect(() => {
    if (selectedEvent === null) {
      return
    }
    const handleMouseDown = (event: MouseEvent) => {
      if (popoverRef.current?.contains(event.target as Node)) {
        return
      }
      close()
    }
    document.addEventListener('mousedown', handleMouseDown)
    return () => document.removeEventListener('mousedown', handleMouseDown)
  }, [selectedEvent, close])

  return { selectedEvent, anchorRect, popoverRef, open, close }
}
