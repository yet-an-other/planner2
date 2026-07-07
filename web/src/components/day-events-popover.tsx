import { useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import type { CalendarEvent } from '@/lib/google-calendar-events'
import { computePopoverPlacement } from '@/lib/popover-placement'
import { formatEventTiming } from '@/lib/event-timing'
import { formatFullDate } from '@/lib/calendar-dates'
import { cn } from '@/lib/utils'

const HEADER_ID = 'day-events-popover-title'
const POPOVER_MAX_WIDTH = 360

/** Fallback anchor when no rect was captured (defensive; the hook always sets one). */
const ZERO_RECT = {
  bottom: 0,
  left: 0,
  top: 0,
  right: 0,
  height: 0,
  width: 0,
  x: 0,
  y: 0,
  toJSON: () => ({}),
} as DOMRect

/** Props for the presentational Day Events Popover. */
export type DayEventsPopoverProps = {
  /** The full ordered set of Calendar Events for the day, or null when closed. */
  dayEvents: CalendarEvent[] | null
  /** The Date Cell's date, shown in the header. Null when closed. */
  date: Date | null
  /** Trigger rect captured at open time; drives fixed placement. */
  anchorRect: DOMRect | null
  /** Called when the user dismisses the popover (close button or Escape). */
  onClose: () => void
  /**
   * Called when the user selects an event to drill into its detail. When
   * omitted (e.g. while disconnected), list items render inert.
   */
  onSelectEvent?: (event: CalendarEvent, trigger: HTMLElement) => void
  /** Ref attached to the popover root so outside-click can tell it apart. */
  popoverRef?: React.RefObject<HTMLDivElement | null>
}

/**
 * Presentational, non-modal Day Events Popover. Portaled to `document.body` so
 * it is never a child of a virtualized Week Row, and fixed-positioned from the
 * trigger rect captured at open time. Lists every Calendar Event attributed to
 * a single Date Cell, mirroring the cell's own ordering (Calendar Event Bars in
 * lane order, then Calendar Event Rows by start time) and item appearance. The
 * Calendar Surface owns open/close lifecycle; this component renders the list,
 * measures its own size for placement, and reports dismissal via `onClose`.
 *
 * ADR 0004: this is a layout-overflow reveal, not a detail reveal — it carries
 * no privacy boundary of its own. The drill-through (`onSelectEvent`) is the
 * only connection-gated part and is supplied by the surface only while connected.
 */
export function DayEventsPopover({
  dayEvents,
  date,
  anchorRect,
  onClose,
  onSelectEvent,
  popoverRef,
}: DayEventsPopoverProps) {
  const [popoverHeight, setPopoverHeight] = useState(0)
  const innerRef = useRef<HTMLDivElement | null>(null)

  // Measure the rendered popover so vertical placement can flip above / clamp
  // when it would overflow. useLayoutEffect runs before paint (no flash).
  useLayoutEffect(() => {
    const el = innerRef.current
    if (!el) {
      return
    }
    const measure = () => setPopoverHeight(el.offsetHeight)
    measure()
    if (typeof ResizeObserver === 'undefined') {
      return
    }
    const observer = new ResizeObserver(measure)
    observer.observe(el)
    return () => observer.disconnect()
  }, [dayEvents])

  if (!dayEvents || !date) {
    return null
  }

  const interactive = typeof onSelectEvent === 'function'
  const viewport = { width: window.innerWidth, height: window.innerHeight }
  const placement = computePopoverPlacement({
    anchorRect: anchorRect ?? ZERO_RECT,
    viewport,
    popover: {
      width: Math.min(POPOVER_MAX_WIDTH, viewport.width * 0.9),
      height: popoverHeight,
    },
  })

  return createPortal(
    <div
      aria-labelledby={HEADER_ID}
      aria-modal="false"
      className={cn(
        'fixed z-50 max-h-[80vh] overflow-y-auto',
        'rounded-lg border border-[#d8d1bd] bg-[#f5f1e6] text-[#252819] shadow-lg',
      )}
      onKeyDown={(keyEvent) => {
        if (keyEvent.key === 'Escape') {
          onClose()
        }
      }}
      ref={(el) => {
        innerRef.current = el
        if (popoverRef) {
          popoverRef.current = el
        }
      }}
      role="dialog"
      style={{
        position: 'fixed',
        top: placement.top,
        left: placement.left,
        width: placement.width,
      }}
      tabIndex={-1}
    >
      <div className="flex items-center justify-between gap-2 border-b border-[#d8d1bd] px-4 pb-2 pt-3">
        <h2 className="min-w-0 flex-1 text-sm font-extrabold leading-tight" id={HEADER_ID}>
          {formatFullDate(date)}
        </h2>
        <button
          aria-label="Close"
          autoFocus
          className="-mr-1 shrink-0 rounded p-1 text-[#777b60] hover:text-[#252819] focus:outline-none focus-visible:ring-2 focus-visible:ring-[#777b60]"
          onClick={onClose}
          type="button"
        >
          <svg
            aria-hidden="true"
            className="h-4 w-4"
            fill="none"
            stroke="currentColor"
            strokeWidth={2}
            viewBox="0 0 24 24"
          >
            <path d="M6 6l12 12M18 6L6 18" strokeLinecap="round" />
          </svg>
        </button>
      </div>

      <ul className="px-2 py-2">
        {dayEvents.map((event) => (
          <li key={event.id}>
            <DayEventItem event={event} interactive={interactive} onSelect={onSelectEvent} />
          </li>
        ))}
      </ul>
    </div>,
    document.body,
  )
}

type DayEventItemProps = {
  event: CalendarEvent
  interactive: boolean
  onSelect?: (event: CalendarEvent, trigger: HTMLElement) => void
}

/** A single event in the day list, mirroring its cell counterpart's appearance. */
function DayEventItem({ event, interactive, onSelect }: DayEventItemProps) {
  if (event.kind === 'row') {
    const label = `${event.title}, ${event.startTime}`
    const className = cn(
      'flex w-full items-center gap-2 truncate rounded px-2 py-1 text-left text-xs leading-5',
      interactive &&
        'cursor-pointer hover:bg-[#e7e1cf] focus:bg-[#e7e1cf] focus:outline-none focus-visible:ring-2 focus-visible:ring-[#777b60]',
    )
    const inner = (
      <>
        <span
          aria-hidden="true"
          className="inline-block h-2 w-2 shrink-0 rounded-full"
          style={{ backgroundColor: event.color }}
        />
        <span className="shrink-0 tabular-nums text-[#777b60]">{event.startTime}</span>
        <span className="truncate">{event.title}</span>
      </>
    )

    if (interactive) {
      return (
        <button
          aria-label={`${label} — open details`}
          className={className}
          onClick={(e) => onSelect?.(event, e.currentTarget)}
          type="button"
        >
          {inner}
        </button>
      )
    }
    return (
      <div className={className} title={label}>
        {inner}
      </div>
    )
  }

  // Calendar Event Bar: color swatch + title + a timing label (All day / span).
  const timingLabel = formatEventTiming(event.timing)
  const label = `${event.title}, ${timingLabel}`
  const className = cn(
    'flex w-full items-center gap-2 rounded px-2 py-1 text-left text-xs leading-5',
    interactive &&
      'cursor-pointer hover:bg-[#e7e1cf] focus:bg-[#e7e1cf] focus:outline-none focus-visible:ring-2 focus-visible:ring-[#777b60]',
  )
  const inner = (
    <>
      <span
        aria-hidden="true"
        className="inline-block h-2 w-2 shrink-0 rounded-full"
        style={{ backgroundColor: event.color }}
      />
      <span className="min-w-0 flex-1 truncate font-medium">{event.title}</span>
      <span className="shrink-0 text-[10px] text-[#8b8f72]">{timingLabel}</span>
    </>
  )

  if (interactive) {
    return (
      <button
        aria-label={`${label} — open details`}
        className={className}
        onClick={(e) => onSelect?.(event, e.currentTarget)}
        type="button"
      >
        {inner}
      </button>
    )
  }
  return (
    <div className={className} title={label}>
      {inner}
    </div>
  )
}
