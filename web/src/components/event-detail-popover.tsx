import { createPortal } from 'react-dom'
import type { CalendarEvent } from '@/lib/google-calendar-events'
import { formatEventTiming } from '@/lib/event-timing'
import { cn } from '@/lib/utils'

const TITLE_ID = 'event-detail-popover-title'

type EventDetailPopoverProps = {
  /** The Calendar Event to show detail for. When null, nothing is rendered. */
  event: CalendarEvent | null
  /** Trigger rect captured at open time; drives fixed placement. */
  anchorRect: DOMRect | null
  /** Called when the user dismisses the popover (close button or Escape). */
  onClose: () => void
}

/**
 * Presentational, non-modal Event Detail Popover. Portaled to `document.body`
 * so it is never a child of a virtualized Week Row, and fixed-positioned from
 * the trigger rect captured at open time. The Calendar Surface owns open/close
 * lifecycle; this component renders detail and reports dismissal via `onClose`.
 *
 * Slice 1 of PRD #003 renders the title, normalized timing, and the Google
 * Calendar link. Location/description/attendees are rendered in slice 2.
 */
export function EventDetailPopover({
  event,
  anchorRect,
  onClose,
}: EventDetailPopoverProps) {
  if (!event) {
    return null
  }

  const top = anchorRect ? Math.round(anchorRect.bottom + 8) : 0
  const left = anchorRect ? Math.round(anchorRect.left) : 0

  return createPortal(
    <div
      aria-labelledby={TITLE_ID}
      aria-modal="false"
      className={cn(
        'fixed z-50 w-[min(360px,90vw)] max-h-[80vh] overflow-y-auto',
        'rounded-lg border border-[#d8d1bd] bg-[#f5f1e6] text-[#252819] shadow-lg',
      )}
      onKeyDown={(event) => {
        if (event.key === 'Escape') {
          onClose()
        }
      }}
      role="dialog"
      style={{ position: 'fixed', top, left }}
      tabIndex={-1}
    >
      <div className="flex items-start gap-2 border-l-4 px-4 pb-3 pt-3" style={{ borderLeftColor: event.color }}>
        <h2 className="min-w-0 flex-1 text-base font-bold leading-tight" id={TITLE_ID}>
          {event.title}
        </h2>
        <button
          aria-label="Close"
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
