import { useMemo, useRef, useState } from 'react'
import { useVirtualizer } from '@tanstack/react-virtual'
import {
  addDays,
  formatFullDate,
  formatVisibleMonth,
  getCalendarRange,
  isSameCalendarDate,
  isWeekend,
  toISODate,
  toLocalDate,
} from '@/lib/calendar-dates'
import { cn } from '@/lib/utils'

const WEEK_ROW_HEIGHT = 96
const WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
const WEEK_ROW_OVERSCAN = 20

export function CalendarSurface() {
  const scrollParentRef = useRef<HTMLDivElement>(null)
  const today = useMemo(() => toLocalDate(new Date()), [])
  const range = useMemo(() => getCalendarRange(today), [today])
  const [topWeekIndex, setTopWeekIndex] = useState(range.todayWeekIndex)

  // TanStack Virtual intentionally returns non-memoizable helpers; keep the virtualizer local to this component.
  // eslint-disable-next-line react-hooks/incompatible-library
  const weekVirtualizer = useVirtualizer({
    count: range.weekCount,
    getScrollElement: () => scrollParentRef.current,
    estimateSize: () => WEEK_ROW_HEIGHT,
    overscan: WEEK_ROW_OVERSCAN,
    initialOffset: range.todayWeekIndex * WEEK_ROW_HEIGHT,
  })

  const visibleWeekStart = useMemo(
    () => addDays(range.start, topWeekIndex * 7),
    [range.start, topWeekIndex],
  )
  const visibleMonth = formatVisibleMonth(visibleWeekStart)

  function updateTopWeekIndex() {
    const scrollParent = scrollParentRef.current

    if (!scrollParent) {
      return
    }

    const nextTopWeekIndex = clamp(
      Math.floor(scrollParent.scrollTop / WEEK_ROW_HEIGHT),
      0,
      range.weekCount - 1,
    )

    setTopWeekIndex((currentTopWeekIndex) =>
      currentTopWeekIndex === nextTopWeekIndex
        ? currentTopWeekIndex
        : nextTopWeekIndex,
    )
  }

  return (
    <main className="flex h-svh min-h-0 flex-col overflow-hidden bg-background text-foreground">
      <header className="shrink-0 border-b border-border bg-background/95 backdrop-blur">
        <div className="flex h-16 items-center px-4 sm:px-6">
          <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">
            {visibleMonth}
          </h1>
        </div>
        <div className="grid h-10 grid-cols-7 border-t border-border text-xs font-medium uppercase tracking-[0.2em] text-muted-foreground">
          {WEEKDAY_LABELS.map((weekday, index) => (
            <div
              className={cn(
                'flex items-center justify-center border-r border-border last:border-r-0',
                index >= 5 && 'bg-muted/20',
              )}
              key={weekday}
            >
              {weekday}
            </div>
          ))}
        </div>
      </header>

      <div
        aria-label="Calendar Surface"
        className="min-h-0 flex-1 overflow-y-auto overscroll-contain"
        onScroll={updateTopWeekIndex}
        ref={scrollParentRef}
      >
        <div
          className="relative w-full"
          style={{ height: weekVirtualizer.getTotalSize() }}
        >
          {weekVirtualizer.getVirtualItems().map((virtualWeek) => {
            const weekStart = addDays(range.start, virtualWeek.index * 7)

            return (
              <div
                className="absolute left-0 top-0 grid w-full grid-cols-7 border-b border-border"
                key={virtualWeek.key}
                style={{
                  height: virtualWeek.size,
                  transform: `translateY(${virtualWeek.start}px)`,
                }}
              >
                {WEEKDAY_LABELS.map((weekday, dayIndex) => {
                  const date = addDays(weekStart, dayIndex)
                  const todayCell = isSameCalendarDate(date, today)
                  const weekendCell = isWeekend(date)

                  return (
                    <div
                      className={cn(
                        'relative border-r border-border p-3 last:border-r-0 sm:p-4',
                        weekendCell && 'bg-muted/20 text-muted-foreground',
                      )}
                      key={`${virtualWeek.key}-${weekday}`}
                    >
                      <time
                        aria-label={`${todayCell ? 'Today, ' : ''}${formatFullDate(date)}`}
                        className={cn(
                          'inline-flex h-8 min-w-8 items-center justify-center rounded-full px-2 text-sm font-medium tabular-nums',
                          todayCell &&
                            'bg-primary text-primary-foreground shadow-sm',
                        )}
                        dateTime={toISODate(date)}
                      >
                        {date.getDate()}
                      </time>
                    </div>
                  )
                })}
              </div>
            )
          })}
        </div>
      </div>
    </main>
  )
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max)
}
