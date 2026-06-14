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
import { PRODUCT_VERSION } from '@/lib/product-version'
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

  function jumpToToday() {
    const behavior = prefersReducedMotion() ? 'auto' : 'smooth'

    weekVirtualizer.scrollToIndex(range.todayWeekIndex, {
      align: 'start',
      behavior,
    })

    if (behavior === 'auto') {
      setTopWeekIndex(range.todayWeekIndex)
    }
  }

  return (
    <main className="flex h-svh min-h-0 flex-col overflow-hidden bg-background text-foreground">
      <header className="shrink-0 border-b border-[#d8d1bd] bg-[#f5f1e6] text-[#252819] shadow-sm">
        <div className="grid h-20 grid-cols-[minmax(0,1fr)_auto_minmax(0,1fr)] items-center px-4 sm:px-6">
          <div className="justify-self-start">
            <div className="inline-flex flex-col">
              <div className="whitespace-nowrap text-[clamp(18px,6vw,40px)] font-extrabold leading-none tracking-[-0.08em] text-[#777b60]">
                The Planner
              </div>
              <div className="mt-1 self-end text-[10px] font-medium leading-none tracking-[0.28em] text-[#8b8f72]">
                v{PRODUCT_VERSION}
              </div>
            </div>
          </div>
          <h1 className="justify-self-center whitespace-nowrap text-[clamp(14px,4vw,26px)] font-extrabold tracking-tight">
            <button
              aria-label={`Return to Today, ${formatFullDate(today)}`}
              className="rounded-full px-4 py-2 transition-colors hover:bg-[#ebe4d2] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f] focus-visible:ring-offset-2 focus-visible:ring-offset-[#f5f1e6]"
              onClick={jumpToToday}
              title="Return to Today"
              type="button"
            >
              {visibleMonth}
            </button>
          </h1>
          <div aria-hidden="true" />
        </div>
        <div className="grid h-10 grid-cols-7 border-t border-[#d8d1bd] text-xs font-medium uppercase tracking-[0.2em] text-[#6f725a]">
          {WEEKDAY_LABELS.map((weekday, index) => (
            <div
              className={cn(
                'flex items-center justify-center border-r border-[#d8d1bd] last:border-r-0',
                index >= 5 && 'bg-[#eee8d8]/70',
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

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}
