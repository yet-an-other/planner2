import { useState } from 'react'
import { Dialog } from 'radix-ui'
import { Check } from 'lucide-react'
import type { SourceCalendar } from '@/lib/google-calendar-events'
import type { SourceCalendarId } from '@/lib/use-source-calendars'
import { cn } from '@/lib/utils'

type SourceCalendarPickerProps = {
  /** Every available Source Calendar the user can choose from. */
  available: SourceCalendar[]
  /** The currently-selected Source Calendar ids (the starting draft). */
  selectedIds: SourceCalendarId[]
  /** Apply the draft selection and close. */
  onSave: (ids: SourceCalendarId[]) => void
  /** Discard the draft and close. */
  onCancel: () => void
}

/**
 * Presentational modal Source Calendar Picker. The Calendar Surface owns open/
 * close lifecycle (it mounts this component only while the picker is open); this
 * component holds the in-progress draft, enforces minimum-one (Save is disabled
 * at zero), and reports the outcome via `onSave` / `onCancel`.
 *
 * Built on Radix Dialog for focus trapping, Escape, and outside-click dismiss;
 * rows are native checkboxes for screen-reader-friendly checked state.
 */
export function SourceCalendarPicker({
  available,
  selectedIds,
  onSave,
  onCancel,
}: SourceCalendarPickerProps) {
  const [draft, setDraft] = useState<Set<SourceCalendarId>>(
    () => new Set(selectedIds),
  )

  const ordered = orderForPicker(available)
  const primaryId = available.find((calendar) => calendar.primary)?.id

  function toggle(id: SourceCalendarId) {
    setDraft((previous) => {
      const next = new Set(previous)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }

  function selectAll() {
    setDraft(new Set(available.map((calendar) => calendar.id)))
  }

  function resetToPrimary() {
    setDraft(new Set(primaryId ? [primaryId] : ordered.slice(0, 1).map((c) => c.id)))
  }

  return (
    <Dialog.Root open onOpenChange={(open) => !open && onCancel()}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-black/40 data-[state=open]:animate-in data-[state=open]:fade-in" />
        <Dialog.Content
          aria-describedby="source-calendar-picker-description"
          className="fixed left-1/2 top-1/2 z-50 flex max-h-[80vh] w-[min(92vw,420px)] -translate-x-1/2 -translate-y-1/2 flex-col overflow-hidden rounded-xl border border-[#d8d1bd] bg-[#f5f1e6] text-[#252819] shadow-xl"
        >
          <div className="flex items-center justify-between border-b border-[#d8d1bd] px-4 py-3">
            <Dialog.Title className="text-sm font-extrabold tracking-tight">
              Calendars
            </Dialog.Title>
          </div>
          <Dialog.Description
            className="sr-only"
            id="source-calendar-picker-description"
          >
            Choose which calendars contribute events to the Calendar Surface.
          </Dialog.Description>

          <div className="flex items-center gap-3 border-b border-[#d8d1bd] px-4 py-2 text-xs font-medium">
            <button
              className="rounded-full px-2 py-1 text-[#384052] transition-colors hover:bg-[#ebe4d2] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f]"
              onClick={selectAll}
              type="button"
            >
              Select all
            </button>
            <button
              className="rounded-full px-2 py-1 text-[#384052] transition-colors hover:bg-[#ebe4d2] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f]"
              onClick={resetToPrimary}
              type="button"
            >
              Reset to primary
            </button>
          </div>

          <ul className="min-h-0 flex-1 divide-y divide-[#e3dcc8] overflow-y-auto">
            {ordered.map((calendar) => {
              const checked = draft.has(calendar.id)
              return (
                <li key={calendar.id}>
                  <label className="flex cursor-pointer items-center gap-3 px-4 py-2.5 transition-colors hover:bg-[#ebe4d2]">
                    <input
                      aria-label={`${calendar.summary}${calendar.primary ? ' (primary calendar)' : ''}`}
                      checked={checked}
                      onChange={() => toggle(calendar.id)}
                      type="checkbox"
                      className="h-4 w-4 shrink-0 accent-[#7d855f]"
                    />
                    <span
                      aria-hidden="true"
                      className="h-3.5 w-3.5 shrink-0 rounded-full border border-black/10"
                      style={{ backgroundColor: calendar.backgroundColor }}
                    />
                    <span className="min-w-0 flex-1 truncate text-sm font-medium">
                      {calendar.summary}
                    </span>
                    {calendar.primary && (
                      <span className="shrink-0 rounded-full bg-[#e5e7df] px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide text-[#777b60]">
                        Primary
                      </span>
                    )}
                  </label>
                </li>
              )
            })}
          </ul>

          <div className="flex justify-end gap-2 border-t border-[#d8d1bd] px-4 py-3">
            <button
              className="inline-flex h-9 items-center justify-center rounded-full px-4 text-sm font-medium text-[#384052] transition-colors hover:bg-[#ebe4d2] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f]"
              onClick={onCancel}
              type="button"
            >
              Cancel
            </button>
            <button
              className={cn(
                'inline-flex h-9 items-center gap-1.5 justify-center rounded-full px-4 text-sm font-semibold text-white shadow-sm transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f]',
                draft.size === 0
                  ? 'cursor-not-allowed bg-[#b9bd9f]'
                  : 'bg-[#7d855f] hover:bg-[#6b7152]',
              )}
              disabled={draft.size === 0}
              onClick={() => onSave([...draft])}
              type="button"
            >
              <Check aria-hidden="true" className="h-4 w-4" strokeWidth={2.6} />
              Save
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}

/** Primary calendar first (with a badge), then the rest alphabetical by summary. */
function orderForPicker(calendars: SourceCalendar[]): SourceCalendar[] {
  return [...calendars].sort((a, b) => {
    if (a.primary !== b.primary) {
      return a.primary ? -1 : 1
    }
    return a.summary.localeCompare(b.summary)
  })
}
