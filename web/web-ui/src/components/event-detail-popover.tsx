import { useLayoutEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import { MapPin } from 'lucide-react'
import type { Attendee, CalendarEvent } from '@/lib/google-calendar-events'
import { buildLocationHref } from '@/lib/location-links'
import { computePopoverPlacement } from '@/lib/popover-placement'
import { formatEventTiming } from '@/lib/event-timing'
import { splitTextIntoLinkSegments } from '@/lib/text-links'
import { cn } from '@/lib/utils'

const TITLE_ID = 'event-detail-popover-title'
const MAX_ATTENDEES = 5
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

const RESPONSE_STATUS_LABELS: Record<Attendee['responseStatus'], string> = {
  accepted: 'accepted',
  declined: 'declined',
  tentative: 'tentative',
  needsAction: 'invited',
  unknown: 'unknown',
}

/** Name shown for an attendee: display name when present, email otherwise. */
function attendeeLabel(attendee: Attendee): string {
  return attendee.displayName ?? attendee.email
}

type EventDetailPopoverProps = {
  /** The Calendar Event to show detail for. When null, nothing is rendered. */
  event: CalendarEvent | null
  /** Trigger rect captured at open time; drives fixed placement. */
  anchorRect: DOMRect | null
  /** Called when the user dismisses the popover (close button or Escape). */
  onClose: () => void
  /** Ref attached to the popover root so outside-click can tell it apart. */
  popoverRef?: React.RefObject<HTMLDivElement | null>
}

/**
 * Presentational, non-modal Event Detail Popover. Portaled to `document.body`
 * so it is never a child of a virtualized Week Row, and fixed-positioned from
 * the trigger rect captured at open time. Placement is computed by the pure
 * `computePopoverPlacement` module, which clamps horizontally and flips above
 * / clamps vertically so the popover is always fully on screen. The Calendar
 * Surface owns open/close lifecycle; this component renders detail, measures
 * its own size, and reports dismissal via `onClose`.
 *
 * PRD #003 renders the title, normalized timing, location, description,
 * attendees, and the Google Calendar link.
 */
export function EventDetailPopover({
  event,
  anchorRect,
  onClose,
  popoverRef,
}: EventDetailPopoverProps) {
  const [popoverHeight, setPopoverHeight] = useState(0)
  const innerRef = useRef<HTMLDivElement | null>(null)

  // Measure the rendered popover so vertical placement can flip above / clamp
  // when it would overflow. useLayoutEffect runs before paint, so the first
  // painted frame already reflects the measured size (no flash).
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
  }, [event])

  if (!event) {
    return null
  }

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
      aria-labelledby={TITLE_ID}
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
      <div className="flex items-start gap-2 border-l-4 px-4 pb-3 pt-3" style={{ borderLeftColor: event.color }}>
        <h2 className="min-w-0 flex-1 text-base font-bold leading-tight" id={TITLE_ID}>
          {event.title}
        </h2>
        <button
          aria-label="Close"
          autoFocus
          className="-mr-1 -mt-1 shrink-0 rounded p-1 text-[#777b60] hover:text-[#252819] focus:outline-none focus-visible:ring-2 focus-visible:ring-[#777b60]"
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

      <dl className="space-y-2 px-4 pb-3">
        <div>
          <dt className="text-[10px] font-semibold uppercase tracking-[0.18em] text-[#8b8f72]">
            When
          </dt>
          <dd className="mt-0.5 text-sm">{formatEventTiming(event.timing)}</dd>
        </div>

        {event.detail.location !== null && (
          <div>
            <dt className="text-[10px] font-semibold uppercase tracking-[0.18em] text-[#8b8f72]">
              Where
            </dt>
            <dd className="mt-0.5 text-sm">
              <LocationText location={event.detail.location} />
            </dd>
          </div>
        )}

        {event.detail.description !== null && (
          <div>
            <dt className="text-[10px] font-semibold uppercase tracking-[0.18em] text-[#8b8f72]">
              Notes
            </dt>
            <dd
              className="mt-0.5 max-h-40 whitespace-pre-wrap text-sm"
              data-testid="description"
              style={{ overflowY: 'auto' }}
            >
              <DescriptionText text={event.detail.description} />
            </dd>
          </div>
        )}

        {event.detail.attendees.length > 0 && (
          <div>
            <dt className="text-[10px] font-semibold uppercase tracking-[0.18em] text-[#8b8f72]">
              Attendees
            </dt>
            <AttendeeList attendees={event.detail.attendees} />
          </div>
        )}
      </dl>

      {event.detail.htmlLink !== null && (
        <div className="border-t border-[#d8d1bd] px-4 py-3">
          <a
            className="text-sm font-medium text-[#252819] underline underline-offset-2 hover:text-[#777b60]"
            href={event.detail.htmlLink}
            rel="noopener noreferrer"
            target="_blank"
          >
            Open in Google Calendar →
          </a>
        </div>
      )}
    </div>,
    document.body,
  )
}

/**
 * Renders the location as an actionable link. A place/address string becomes
 * a pin-icon Maps link followed by the location as plain text; a location that
 * is itself an http(s) URL is rendered as a direct text link. The location data
 * model stays `string | null`; this is purely presentational.
 */
function LocationText({ location }: { location: string }) {
  const href = buildLocationHref(location)

  if (href.kind === 'url') {
    return (
      <a
        className="text-[#2952a3] underline underline-offset-2 hover:text-[#777b60]"
        href={href.url}
        rel="noopener noreferrer"
        target="_blank"
      >
        {location}
      </a>
    )
  }

  return (
    <span className="inline-flex items-start gap-1">
      <a
        aria-label="Open in Google Maps"
        className="mt-0.5 shrink-0 text-[#2952a3] hover:text-[#777b60] focus:outline-none focus-visible:ring-2 focus-visible:ring-[#777b60]"
        href={href.url}
        rel="noopener noreferrer"
        target="_blank"
      >
        <MapPin aria-hidden="true" className="h-3.5 w-3.5" />
      </a>
      <span>{location}</span>
    </span>
  )
}

/**
 * Renders the description plain text with any `http(s)` URLs turned into
 * external links. The description is stored as plain text (HTML is stripped at
 * normalization); linkification is purely presentational, so the data model and
 * its "plain-text notes" invariant are unchanged.
 */
function DescriptionText({ text }: { text: string }) {
  const segments = splitTextIntoLinkSegments(text)
  return (
    <>
      {segments.map((segment, index) =>
        segment.kind === 'link' ? (
          <a
            className="text-[#2952a3] underline underline-offset-2 hover:text-[#777b60]"
            href={segment.url}
            key={`link-${index}`}
            rel="noopener noreferrer"
            target="_blank"
          >
            {segment.value}
          </a>
        ) : (
          <span key={`text-${index}`}>{segment.value}</span>
        ),
      )}
    </>
  )
}

/** Renders the attendee list. The section is omitted entirely when empty. */
function AttendeeList({ attendees }: { attendees: Attendee[] }) {
  const visible = attendees.slice(0, MAX_ATTENDEES)
  const overflow = attendees.length - visible.length

  return (
    <dd className="mt-0.5 space-y-0.5 text-sm">
      {visible.map((attendee) => (
        <div className="flex items-baseline justify-between gap-2" key={`${attendee.email}-${attendee.displayName ?? ''}`}>
          <span className="truncate">{attendeeLabel(attendee)}</span>
          <span className="shrink-0 text-xs text-[#8b8f72]">
            {RESPONSE_STATUS_LABELS[attendee.responseStatus]}
          </span>
        </div>
      ))}
      {overflow > 0 && <div className="text-xs text-[#8b8f72]">+{overflow} more</div>}
    </dd>
  )
}
