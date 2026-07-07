import { useCallback, useEffect, useRef, useState } from 'react'
import type { CalendarEvent } from './google-calendar-events'

/** State and actions for the Day Events Popover, owned by the Calendar Surface. */
export type DayEventsPopoverController = {
  /** The full ordered set of events for the open day, or null when closed. */
  dayEvents: CalendarEvent[] | null
  /** The Date Cell's date for the open day, or null when closed. */
  date: Date | null
  /** Trigger rect captured at open time; drives the popover's fixed placement. */
  anchorRect: DOMRect | null
  /** Ref attached to the popover root so outside-click can tell it apart. */
  popoverRef: React.RefObject<HTMLDivElement | null>
  /** Summon the popover for a day, anchored to the element that triggered it. */
  open: (dayEvents: CalendarEvent[], date: Date, trigger: HTMLElement) => void
  /** Dismiss the popover. A no-op (no focus theft) when nothing is open. */
  close: () => void
}

type UseDayEventsPopoverParams = {
  /** Ref to the Calendar Surface scroll container; scrolling it closes the popover. */
  scrollContainerRef: React.RefObject<HTMLElement | null>
}

/**
 * Owns the Day Events Popover lifecycle: which day's events are shown, the
 * anchor rect captured at open time, the single-cardinality rule, and the
 * dismiss triggers that depend on the surface (close-on-scroll, outside-click).
 * Focus is returned to the opening trigger on any close.
 *
 * Unlike the Event Detail Popover controller, this does NOT close on disconnect:
 * the Day Events Popover is a layout-overflow reveal, not a detail reveal, and
 * carries no privacy boundary of its own (ADR 0004). It will show Saved Busy
 * Blocks unchanged once they ship.
 *
 * The presentational `<DayEventsPopover>` owns focus-on-open (focusing its
 * close button); this hook owns focus-return-on-close uniformly across every
 * dismiss path.
 */
export function useDayEventsPopover({
  scrollContainerRef,
}: UseDayEventsPopoverParams): DayEventsPopoverController {
  const [dayEvents, setDayEvents] = useState<CalendarEvent[] | null>(null)
  const [date, setDate] = useState<Date | null>(null)
  const [anchorRect, setAnchorRect] = useState<DOMRect | null>(null)

  const triggerRef = useRef<HTMLElement | null>(null)
  const popoverRef = useRef<HTMLDivElement | null>(null)
  // Mirror open state into a ref so listeners can read it without re-binding.
  const dayEventsRef = useRef<CalendarEvent[] | null>(dayEvents)
  useEffect(() => {
    dayEventsRef.current = dayEvents
  }, [dayEvents])

  const open = useCallback(
    (dayEvents: CalendarEvent[], date: Date, trigger: HTMLElement) => {
      triggerRef.current = trigger
      setDayEvents(dayEvents)
      setDate(date)
      setAnchorRect(trigger.getBoundingClientRect())
    },
    [],
  )

  const close = useCallback(() => {
    if (dayEventsRef.current === null) {
      // Already closed: bail so listeners (scroll, outside-click) never steal focus.
      return
    }
    setDayEvents(null)
    setDate(null)
    setAnchorRect(null)
  }, [])

  // Return focus to the trigger whenever the popover transitions open -> closed,
  // regardless of which dismiss path caused it.
  const prevOpenRef = useRef<boolean>(dayEvents !== null)
  useEffect(() => {
    const wasOpen = prevOpenRef.current
    const isOpen = dayEvents !== null
    if (wasOpen && !isOpen) {
      const trigger = triggerRef.current
      if (trigger && document.contains(trigger)) {
        trigger.focus()
      }
      triggerRef.current = null
    }
    prevOpenRef.current = isOpen
  }, [dayEvents])

  // Close when the Calendar Surface is scrolled (the virtualization-correctness
  // rule: a popover anchored to a Week Row that scrolls out of view would float
  // orphaned). Passive; a no-op when already closed.
  useEffect(() => {
    const scrollElement = scrollContainerRef.current
    if (!scrollElement) {
      return
    }
    const handleScroll = () => {
      if (dayEventsRef.current !== null) {
        close()
      }
    }
    scrollElement.addEventListener('scroll', handleScroll, { passive: true })
    return () => scrollElement.removeEventListener('scroll', handleScroll)
  }, [scrollContainerRef, close])

  // Close on outside click. Only attached while open; a click inside the popover
  // (or that re-opens via a trigger) is left to the trigger handlers.
  useEffect(() => {
    if (dayEvents === null) {
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
  }, [dayEvents, close])

  return { dayEvents, date, anchorRect, popoverRef, open, close }
}
