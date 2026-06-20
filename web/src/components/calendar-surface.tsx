import { useMemo, useRef, useState } from 'react'
import { useVirtualizer } from '@tanstack/react-virtual'
import {
  addDays,
  formatFullDate,
  formatShortMonth,
  formatVisibleMonth,
  getCalendarRange,
  isSameCalendarDate,
  isWeekend,
  toISODate,
  toLocalDate,
} from '@/lib/calendar-dates'
import { useGoogleAccountConnection } from '@/lib/use-google-account-connection'
import { useCalendarEvents } from '@/lib/use-calendar-events'
import { useEventDetailPopover } from '@/lib/use-event-detail-popover'
import { CalendarHeader } from './calendar-header'
import { EventDetailPopover } from './event-detail-popover'
import { layoutWeekEvents } from '@/lib/event-layout'
import { getContrastTextColor } from '@/lib/text-contrast'
import { cn } from '@/lib/utils'

const WEEK_ROW_HEIGHT = 128
const WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
const WEEK_ROW_OVERSCAN = 20

export function CalendarSurface() {
  const scrollParentRef = useRef<HTMLDivElement>(null)
  const today = useMemo(() => toLocalDate(new Date()), [])
  const range = useMemo(() => getCalendarRange(today), [today])
  const [topWeekIndex, setTopWeekIndex] = useState(range.todayWeekIndex)
  const googleClientId = import.meta.env.VITE_GOOGLE_CLIENT_ID?.trim() ?? ''
  const googleAccountConnection = useGoogleAccountConnection(googleClientId)
  const connection = googleAccountConnection.connection
  // The Fetched Window, scroll-driven slab fetching, and loading/error status
  // live behind this seam; the render module only computes the visible range
  // from scroll position and hands it to maybeFetchMore.
  const { events, status: eventsStatus, maybeFetchMore } = useCalendarEvents({
    connection,
    today,
    range,
  })
  const eventDetailPopover = useEventDetailPopover()

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
  const googleAccountConnected = connection.status === 'connected'
  // Loading (from the events module) takes precedence, then its load error, then
  // the connection status from the Google Account Connection module.
  const effectiveHeaderStatus = eventsStatus ?? googleAccountConnection.status

  function updateTopWeekIndex() {
    const scrollParent = scrollParentRef.current

    if (!scrollParent) {
      return
    }

    const scrollTop = scrollParent.scrollTop
    const nextTopWeekIndex = clamp(
      Math.floor(scrollTop / WEEK_ROW_HEIGHT),
      0,
      range.weekCount - 1,
    )

    setTopWeekIndex((currentTopWeekIndex) =>
      currentTopWeekIndex === nextTopWeekIndex
        ? currentTopWeekIndex
        : nextTopWeekIndex,
    )

    if (connection.status !== 'connected') {
      return
    }

    const bottomWeekIndex = clamp(
      Math.floor((scrollTop + scrollParent.clientHeight) / WEEK_ROW_HEIGHT),
      0,
      range.weekCount - 1,
    )
    maybeFetchMore({
      start: addDays(range.start, nextTopWeekIndex * 7),
      end: addDays(range.start, bottomWeekIndex * 7 + 6),
    })
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
      <CalendarHeader
        today={today}
        visibleMonth={visibleMonth}
        status={effectiveHeaderStatus}
        connected={googleAccountConnected}
        isConfigured={googleAccountConnection.isConfigured}
        profile={
          connection.status === 'connected' ? connection.profile : null
        }
        onJumpToToday={jumpToToday}
        onConnect={googleAccountConnection.connect}
        onDisconnect={googleAccountConnection.disconnect}
      />

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
            const weekLayout = layoutWeekEvents(events, weekStart)
            const dayMaxLane = Array.from({ length: 7 }, () => -1)
            for (const bar of weekLayout.bars) {
              for (let d = bar.startDayIndex; d <= bar.endDayIndex; d++) {
                dayMaxLane[d] = Math.max(dayMaxLane[d], bar.laneIndex)
              }
            }

            return (
              <div
                className="absolute left-0 top-0 grid w-full grid-cols-7 border-b border-border"
                key={virtualWeek.key}
                style={{
                  height: virtualWeek.size,
                  transform: `translateY(${virtualWeek.start}px)`,
                }}
              >
                {/* Event bars layer */}
                <div className="pointer-events-none absolute inset-x-0 top-10 z-10 h-[calc(100%-2.5rem)]">
                  {weekLayout.bars.map((bar) => {
                    const left = (bar.startDayIndex / 7) * 100
                    const width = ((bar.endDayIndex - bar.startDayIndex + 1) / 7) * 100
                    const top = bar.laneIndex * 24
                    const textColor = getContrastTextColor(bar.event.color)
                    const isOpen =
                      eventDetailPopover.selectedEvent?.id === bar.event.id
                    const positionStyle = {
                      left: `${left}%`,
                      width: `${width}%`,
                      top: `${top}px`,
                      backgroundColor: bar.event.color,
                      color: textColor,
                      borderTopLeftRadius: bar.isStartTruncated ? 0 : 4,
                      borderBottomLeftRadius: bar.isStartTruncated ? 0 : 4,
                      borderTopRightRadius: bar.isEndTruncated ? 0 : 4,
                      borderBottomRightRadius: bar.isEndTruncated ? 0 : 4,
                    }

                    if (googleAccountConnected) {
                      return (
                        <button
                          aria-expanded={isOpen}
                          aria-label={`${bar.event.title} — open details`}
                          className={cn(
                            'pointer-events-auto absolute h-[18px] cursor-pointer overflow-hidden truncate pl-4 pr-1 text-left text-[10px] font-medium leading-[18px]',
                          )}
                          key={bar.event.id}
                          onClick={(event) =>
                            eventDetailPopover.open(bar.event, event.currentTarget)
                          }
                          style={positionStyle}
                          title={bar.event.title}
                          type="button"
                        >
                          {bar.event.title}
                        </button>
                      )
                    }

                    return (
                      <div
                        className="absolute h-[18px] overflow-hidden truncate pl-4 pr-1 text-[10px] font-medium leading-[18px]"
                        key={bar.event.id}
                        style={positionStyle}
                        title={bar.event.title}
                      >
                        {bar.event.title}
                      </div>
                    )
                  })}
                </div>

                {WEEKDAY_LABELS.map((weekday, dayIndex) => {
                  const date = addDays(weekStart, dayIndex)
                  const todayCell = isSameCalendarDate(date, today)
                  const weekendCell = isWeekend(date)
                  const monthMarker = date.getDate() === 1
                  const cellLayout = weekLayout.cells[dayIndex]

                  return (
                    <div
                      className={cn(
                        'relative border-r border-border p-1 last:border-r-0 sm:p-1',
                        weekendCell && 'bg-muted/20 text-muted-foreground',
                      )}
                      key={`${virtualWeek.key}-${weekday}`}
                    >
                      {monthMarker && (
                        <div
                          aria-hidden="true"
                          className="absolute inset-y-0 left-0 w-[3px] bg-[#8b8f72]"
                        />
                      )}
                      <div className="flex items-center px-1 justify-between gap-2">
                        <div className="min-w-0">
                          {monthMarker && (
                            <span className="block truncate text-xs font-extrabold uppercase tracking-[0.2em] text-[#6f725a]">
                              {formatShortMonth(date)}
                            </span>
                          )}
                        </div>
                        <time
                          aria-label={`${todayCell ? 'Today, ' : ''}${formatFullDate(date)}`}
                          className={cn(
                            'inline-flex h-8 min-w-8 shrink-0 items-center justify-center rounded-full px-2 text-sm font-medium tabular-nums',
                            todayCell &&
                              'bg-primary text-primary-foreground shadow-sm',
                          )}
                          dateTime={toISODate(date)}
                        >
                          {date.getDate()}
                        </time>
                      </div>

                      {/* Event rows and overflow */}
                      {(() => {
                        const maxLane = dayMaxLane[dayIndex]
                        const cellMarginTop =
                          maxLane >= 0 ? 28 + maxLane * 24 : undefined
                        return (
                          <div
                            className="space-y-[2px] overflow-y-clip"
                            style={
                              cellMarginTop
                                ? { marginTop: `${cellMarginTop}px` }
                                : undefined
                            }
                          >
                            {cellLayout.items.map((item, i) => (
                              <CellItemRenderer
                                key={i}
                                item={item}
                                connected={googleAccountConnected}
                                isOpen={
                                  item.kind === 'row' &&
                                  eventDetailPopover.selectedEvent?.id === item.event.id
                                }
                                onOpen={(trigger) =>
                                  item.kind === 'row' &&
                                  eventDetailPopover.open(item.event, trigger)
                                }
                              />
                            ))}
                          </div>
                        )
                      })()}
                    </div>
                  )
                })}
              </div>
            )
          })}
        </div>
      </div>

      <EventDetailPopover
        anchorRect={eventDetailPopover.anchorRect}
        event={eventDetailPopover.selectedEvent}
        onClose={eventDetailPopover.close}
      />
    </main>
  )
}

type CellItemRendererProps = {
  item: import('@/lib/event-layout').CellItem
  weekLayout: import('@/lib/event-layout').WeekLayout
  connected: boolean
  isOpen: boolean
  onOpen: (trigger: HTMLElement) => void
}

function CellItemRenderer({
  item,
  connected,
  isOpen,
  onOpen,
}: Omit<CellItemRendererProps, 'weekLayout'>) {
  if (item.kind === 'bar') {
    // Bars are rendered once at the week level; skip here to avoid duplication
    return null
  }

  if (item.kind === 'row') {
    const label = `${item.event.title}, ${item.event.startTime} — open details`
    if (connected) {
      return (
        <button
          aria-expanded={isOpen}
          aria-label={label}
          className="flex w-full items-center gap-1 truncate text-left text-[10px] leading-[18px] text-foreground"
          onClick={(event) => onOpen(event.currentTarget)}
          type="button"
        >
          <span className="inline-block h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: item.event.color }} />
          <span className="tabular-nums">{item.event.startTime}</span>
          <span className="truncate">{item.event.title}</span>
        </button>
      )
    }
    return (
      <div className="flex items-center gap-1 truncate text-[10px] leading-[18px] text-foreground">
        <span className="inline-block h-1.5 w-1.5 shrink-0 rounded-full" style={{ backgroundColor: item.event.color }} />
        <span className="tabular-nums">{item.event.startTime}</span>
        <span className="truncate">{item.event.title}</span>
      </div>
    )
  }

  if (item.kind === 'overflow') {
    return (
      <div className="text-[10px] leading-[18px] text-muted-foreground">
        +{item.count} events
      </div>
    )
  }

  return null
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max)
}

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}
