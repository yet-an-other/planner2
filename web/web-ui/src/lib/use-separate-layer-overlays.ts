import { useCallback, useEffect, useRef, useState } from 'react'
import type { CalendarEvent } from './google-calendar-events'
import { calendarEventKey } from './merge-calendar-events'

/** The Event Detail Popover's overlay state (web ADR 0002). */
export type DetailOverlay = {
  /** The Calendar Event currently shown, or null when closed. */
  event: CalendarEvent | null
  /** Trigger rect captured at open time; drives the popover's fixed placement. */
  anchorRect: DOMRect | null
  /** Ref attached to the popover root so outside-click can tell it apart. */
  popoverRef: React.RefObject<HTMLDivElement | null>
}

/** The Day Events Popover's overlay state (web ADR 0004). */
export type DayListOverlay = {
  /** The full ordered set of events for the open day, or null when closed. */
  dayEvents: CalendarEvent[] | null
  /** The Date Cell's date for the open day, or null when closed. */
  date: Date | null
  /** Trigger rect captured at open time; drives the popover's fixed placement. */
  anchorRect: DOMRect | null
  /** Ref attached to the popover root so outside-click can tell it apart. */
  popoverRef: React.RefObject<HTMLDivElement | null>
  /** The "+N more" trigger element captured at open time (anchors drill-through). */
  triggerRef: React.RefObject<HTMLElement | null>
}

/** State and actions for the Calendar Surface's Separate-Layer Overlays. */
export type SeparateLayerOverlays = {
  detail: DetailOverlay
  dayList: DayListOverlay
  /** Summon the Event Detail Popover, closing the day list first (ADR 0004). */
  openDetailFor: (event: CalendarEvent, trigger: HTMLElement) => void
  /** Summon the Day Events Popover, closing the detail popover first (ADR 0004). */
  openDayListFor: (
    dayEvents: CalendarEvent[],
    date: Date,
    trigger: HTMLElement,
  ) => void
  /** Replace the open day list after canonical Calendar Events refresh. */
  updateDayList: (dayEvents: CalendarEvent[]) => void
  /** Dismiss the Event Detail Popover. A no-op (no focus theft) when closed. */
  closeDetail: () => void
  /** Dismiss the Day Events Popover. A no-op (no focus theft) when closed. */
  closeDayList: () => void
}

type UseSeparateLayerOverlaysParams = {
  /** Ref to the Calendar Surface scroll container; scrolling it closes overlays. */
  scrollContainerRef: React.RefObject<HTMLElement | null>
  /** Whether the Google Account Connection is currently connected. */
  isConnected: boolean
  /** Canonical refreshed Calendar Events. */
  events?: CalendarEvent[]
}

/**
 * Owns the Separate-Layer Overlay contract (Web Experience glossary; web
 * ADRs 0002 and 0004) for the Calendar Surface's two overlays: each is
 * anchored to its trigger, non-modal, dismissed by close button, Escape,
 * outside-click, or surface-scroll, and focus returns to the opening
 * trigger on any close. Mutual exclusivity is structural — at most one
 * Separate-Layer Overlay is open at a time because every open closes the
 * sibling here, in the module, for both mouse and keyboard activation.
 *
 * The overlays keep their own payload rules: the Event Detail Popover
 * reconciles against refreshed Calendar Events and closes on Disconnect
 * on This Device (ADR 0002); the Day Events Popover updates its list on
 * refresh and carries no privacy boundary of its own, so it stays open
 * through disconnect (ADR 0004).
 *
 * The presentational popovers own focus-on-open (focusing their close
 * button); this hook owns focus-return-on-close uniformly across every
 * dismiss path, including disconnect (where the trigger is gone, so
 * nothing is focused).
 */
export function useSeparateLayerOverlays({
  scrollContainerRef,
  isConnected,
  events,
}: UseSeparateLayerOverlaysParams): SeparateLayerOverlays {
  const [detailEvent, setDetailEvent] = useState<CalendarEvent | null>(null)
  const [detailAnchorRect, setDetailAnchorRect] = useState<DOMRect | null>(null)
  const [dayEvents, setDayEvents] = useState<CalendarEvent[] | null>(null)
  const [dayDate, setDayDate] = useState<Date | null>(null)
  const [dayAnchorRect, setDayAnchorRect] = useState<DOMRect | null>(null)

  const detailTriggerRef = useRef<HTMLElement | null>(null)
  const dayTriggerRef = useRef<HTMLElement | null>(null)
  const detailPopoverRef = useRef<HTMLDivElement | null>(null)
  const dayPopoverRef = useRef<HTMLDivElement | null>(null)
  // Mirror open state into refs so listeners can read it without re-binding.
  const detailEventRef = useRef<CalendarEvent | null>(detailEvent)
  useEffect(() => {
    detailEventRef.current = detailEvent
  }, [detailEvent])
  const dayEventsRef = useRef<CalendarEvent[] | null>(dayEvents)
  useEffect(() => {
    dayEventsRef.current = dayEvents
  }, [dayEvents])

  const closeDetail = useCallback(() => {
    if (detailEventRef.current === null) {
      // Already closed: bail so listeners (scroll, outside-click) never steal focus.
      return
    }
    setDetailEvent(null)
    setDetailAnchorRect(null)
  }, [])

  const closeDayList = useCallback(() => {
    if (dayEventsRef.current === null) {
      // Already closed: bail so listeners (scroll, outside-click) never steal focus.
      return
    }
    setDayEvents(null)
    setDayDate(null)
    setDayAnchorRect(null)
  }, [])

  const openDetailFor = useCallback(
    (event: CalendarEvent, trigger: HTMLElement) => {
      // Mutual exclusivity (ADR 0004): the sibling closes first, inside the
      // module — the invariant cannot be forgotten at a call site.
      closeDayList()
      detailTriggerRef.current = trigger
      setDetailEvent(event)
      setDetailAnchorRect(trigger.getBoundingClientRect())
    },
    [closeDayList],
  )

  const openDayListFor = useCallback(
    (nextDayEvents: CalendarEvent[], date: Date, trigger: HTMLElement) => {
      // Mutual exclusivity (ADR 0004), as above.
      closeDetail()
      dayTriggerRef.current = trigger
      setDayEvents(nextDayEvents)
      setDayDate(date)
      setDayAnchorRect(trigger.getBoundingClientRect())
    },
    [closeDetail],
  )

  const updateDayList = useCallback((next: CalendarEvent[]) => {
    dayEventsRef.current = next
    setDayEvents(next)
  }, [])

  // Return focus to the trigger whenever an overlay transitions open ->
  // closed, regardless of which dismiss path caused it.
  const prevDetailRef = useRef<CalendarEvent | null>(detailEvent)
  useEffect(() => {
    if (prevDetailRef.current !== null && detailEvent === null) {
      const trigger = detailTriggerRef.current
      if (trigger && document.contains(trigger)) {
        trigger.focus()
      }
      detailTriggerRef.current = null
    }
    prevDetailRef.current = detailEvent
  }, [detailEvent])

  const prevDayOpenRef = useRef<boolean>(dayEvents !== null)
  useEffect(() => {
    const wasOpen = prevDayOpenRef.current
    const isOpen = dayEvents !== null
    if (wasOpen && !isOpen) {
      const trigger = dayTriggerRef.current
      if (trigger && document.contains(trigger)) {
        trigger.focus()
      }
      dayTriggerRef.current = null
    }
    prevDayOpenRef.current = isOpen
  }, [dayEvents])

  // Reconcile an open detail against the canonical refreshed collection.
  useEffect(() => {
    if (!events || detailEventRef.current === null) return
    const selectedKey = calendarEventKey(detailEventRef.current)
    const refreshed = events.find(
      (event) => calendarEventKey(event) === selectedKey,
    )
    if (refreshed) setDetailEvent(refreshed)
    else closeDetail()
  }, [events, closeDetail])

  // Close the detail popover on disconnect (ADR 0002: it is the
  // connection-gated reveal). The day list deliberately stays open (ADR
  // 0004: it discloses nothing the surface does not already present).
  // State is cleared during render (the React "adjust state when a prop
  // changes" pattern); focus return is skipped because the trigger is gone
  // in the disconnected state (handled by the effect's contains check).
  const [prevConnected, setPrevConnected] = useState(isConnected)
  if (prevConnected !== isConnected) {
    setPrevConnected(isConnected)
    if (!isConnected) {
      setDetailEvent(null)
      setDetailAnchorRect(null)
    }
  }

  // Close either overlay when the Calendar Surface is scrolled (the
  // virtualization-correctness rule: an overlay anchored to a Week Row that
  // scrolls out of view would float orphaned). Passive; a no-op when both
  // are closed.
  useEffect(() => {
    const scrollElement = scrollContainerRef.current
    if (!scrollElement) {
      return
    }
    const handleScroll = () => {
      if (detailEventRef.current !== null) {
        closeDetail()
      }
      if (dayEventsRef.current !== null) {
        closeDayList()
      }
    }
    scrollElement.addEventListener('scroll', handleScroll, { passive: true })
    return () => scrollElement.removeEventListener('scroll', handleScroll)
  }, [scrollContainerRef, closeDetail, closeDayList])

  // Close on outside click. Only attached while an overlay is open; a click
  // inside the open popover (or that re-opens via a trigger) is left to the
  // trigger handlers.
  const anyOpen = detailEvent !== null || dayEvents !== null
  useEffect(() => {
    if (!anyOpen) {
      return
    }
    const handleMouseDown = (event: MouseEvent) => {
      if (
        detailEventRef.current !== null &&
        !detailPopoverRef.current?.contains(event.target as Node)
      ) {
        closeDetail()
      }
      if (
        dayEventsRef.current !== null &&
        !dayPopoverRef.current?.contains(event.target as Node)
      ) {
        closeDayList()
      }
    }
    document.addEventListener('mousedown', handleMouseDown)
    return () => document.removeEventListener('mousedown', handleMouseDown)
  }, [anyOpen, closeDetail, closeDayList])

  return {
    detail: {
      event: detailEvent,
      anchorRect: detailAnchorRect,
      popoverRef: detailPopoverRef,
    },
    dayList: {
      dayEvents,
      date: dayDate,
      anchorRect: dayAnchorRect,
      popoverRef: dayPopoverRef,
      triggerRef: dayTriggerRef,
    },
    openDetailFor,
    openDayListFor,
    updateDayList,
    closeDetail,
    closeDayList,
  }
}
