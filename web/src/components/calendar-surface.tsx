import { useEffect, useMemo, useRef, useState } from 'react'
import { useVirtualizer } from '@tanstack/react-virtual'
import { LogIn, LogOut, UserRound } from 'lucide-react'
import {
  addDays,
  addMonths,
  formatFullDate,
  formatShortMonth,
  formatVisibleMonth,
  getCalendarRange,
  isSameCalendarDate,
  isWeekend,
  toISODate,
  toLocalDate,
} from '@/lib/calendar-dates'
import {
  fetchGoogleAccountProfile,
  requestGoogleAccessToken,
  revokeGoogleAccessToken,
  type GoogleAccountProfile,
} from '@/lib/google-account-connection'
import { fetchPrimaryCalendarEvents, type CalendarEvent } from '@/lib/google-calendar-events'
import { mergeCalendarEvents } from '@/lib/merge-calendar-events'
import {
  computeScrollTrigger,
  createFetchedWindow,
  extendFetchedWindow,
  FETCHED_WINDOW_SLAB_MONTHS,
  type FetchedWindow,
} from '@/lib/fetched-window'
import { layoutWeekEvents } from '@/lib/event-layout'
import { getContrastTextColor } from '@/lib/text-contrast'
import { PRODUCT_VERSION } from '@/lib/product-version'
import { cn } from '@/lib/utils'

const WEEK_ROW_HEIGHT = 128
const WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
const WEEK_ROW_OVERSCAN = 20

type GoogleAccountConnectionState =
  | { status: 'connected'; accessToken: string; profile: GoogleAccountProfile }
  | { status: 'disconnected' }

type HeaderStatus = {
  message: string
  tone: 'info' | 'error'
}

export function CalendarSurface() {
  const scrollParentRef = useRef<HTMLDivElement>(null)
  const today = useMemo(() => toLocalDate(new Date()), [])
  const range = useMemo(() => getCalendarRange(today), [today])
  const [topWeekIndex, setTopWeekIndex] = useState(range.todayWeekIndex)
  const [googleAccountConnection, setGoogleAccountConnection] =
    useState<GoogleAccountConnectionState>({ status: 'disconnected' })
  const [headerStatus, setHeaderStatus] = useState<HeaderStatus | null>(null)
  const [events, setEvents] = useState<CalendarEvent[]>([])
  // The Fetched Window is the source of truth for scroll-trigger decisions. It is
  // stored in a ref rather than state because it is not rendered directly and the
  // scroll handler must always read the most recent edges synchronously.
  const fetchedWindowRef = useRef<FetchedWindow | null>(null)
  const [pendingScrollFetchCount, setPendingScrollFetchCount] = useState(0)

  useEffect(() => {
    if (googleAccountConnection.status !== 'connected') {
      setEvents([])
      fetchedWindowRef.current = null
      return
    }

    const accessToken = googleAccountConnection.accessToken
    const earliest = addMonths(today, -6)
    const latest = addMonths(today, 6)
    const fetchRange = {
      start: earliest,
      end: latest,
    }

    fetchedWindowRef.current = createFetchedWindow(earliest, latest)

    fetchPrimaryCalendarEvents(accessToken, fetchRange)
      .then(setEvents)
      .catch(() => {
        setHeaderStatus({
          message: 'Calendar events could not be loaded',
          tone: 'error',
        })
      })
  }, [googleAccountConnection, today])
  const googleClientId = import.meta.env.VITE_GOOGLE_CLIENT_ID?.trim() ?? ''

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
  const googleAccountConnected = googleAccountConnection.status === 'connected'
  const effectiveHeaderStatus =
    pendingScrollFetchCount > 0
      ? ({ message: 'Loading events…', tone: 'info' } as const)
      : headerStatus ??
        (googleClientId
          ? null
          : { message: 'Google client ID is not configured', tone: 'error' as const })

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

    const fetchedWindow = fetchedWindowRef.current
    if (fetchedWindow && googleAccountConnection.status === 'connected') {
      const bottomWeekIndex = clamp(
        Math.floor((scrollTop + scrollParent.clientHeight) / WEEK_ROW_HEIGHT),
        0,
        range.weekCount - 1,
      )
      const visibleRange = {
        start: addDays(range.start, nextTopWeekIndex * 7),
        end: addDays(range.start, bottomWeekIndex * 7 + 6),
      }
      const trigger = computeScrollTrigger(visibleRange, fetchedWindow, undefined, {
        start: range.start,
        end: range.end,
      })
      if (trigger === 'fetch-future') {
        fetchNextFutureSlab(googleAccountConnection.accessToken, fetchedWindow)
      } else if (trigger === 'fetch-past') {
        fetchNextPastSlab(googleAccountConnection.accessToken, fetchedWindow)
      }
    }
  }

  function fetchNextFutureSlab(accessToken: string, fetchedWindow: FetchedWindow) {
    const extended = extendFetchedWindow(
      fetchedWindow,
      'future',
      FETCHED_WINDOW_SLAB_MONTHS,
      { start: range.start, end: range.end },
    )

    // The module clamps the new edge to the Extended Calendar Range, so a no-op
    // move means the window has already reached the far edge.
    if (extended.latest.getTime() <= fetchedWindow.latest.getTime()) {
      return
    }

    const slabRange = { start: fetchedWindow.latest, end: extended.latest }
    // Optimistically extend the Fetched Window so repeated scroll events in the
    // same trigger zone do not fire the same slab twice. Rolled back on failure.
    fetchedWindowRef.current = extended
    setPendingScrollFetchCount((count) => count + 1)

    fetchPrimaryCalendarEvents(accessToken, slabRange)
      .then((slabEvents) => {
        setEvents((previous) => mergeCalendarEvents(previous, slabEvents))
      })
      .catch(() => {
        const current = fetchedWindowRef.current
        if (current && current.latest.getTime() === extended.latest.getTime()) {
          fetchedWindowRef.current = { ...current, latest: fetchedWindow.latest }
        }
      })
      .finally(() => {
        setPendingScrollFetchCount((count) => count - 1)
      })
  }

  function fetchNextPastSlab(accessToken: string, fetchedWindow: FetchedWindow) {
    const extended = extendFetchedWindow(
      fetchedWindow,
      'past',
      FETCHED_WINDOW_SLAB_MONTHS,
      { start: range.start, end: range.end },
    )

    // The module clamps the new edge to the Extended Calendar Range, so a no-op
    // move means the window has already reached the near edge.
    if (extended.earliest.getTime() >= fetchedWindow.earliest.getTime()) {
      return
    }

    const slabRange = { start: extended.earliest, end: fetchedWindow.earliest }
    // Optimistically extend the Fetched Window so repeated scroll events in the
    // same trigger zone do not fire the same slab twice. Rolled back on failure.
    fetchedWindowRef.current = extended
    setPendingScrollFetchCount((count) => count + 1)

    fetchPrimaryCalendarEvents(accessToken, slabRange)
      .then((slabEvents) => {
        setEvents((previous) => mergeCalendarEvents(previous, slabEvents))
      })
      .catch(() => {
        const current = fetchedWindowRef.current
        if (current && current.earliest.getTime() === extended.earliest.getTime()) {
          fetchedWindowRef.current = {
            ...current,
            earliest: fetchedWindow.earliest,
          }
        }
      })
      .finally(() => {
        setPendingScrollFetchCount((count) => count - 1)
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

  function connectGoogleAccount() {
    if (!googleClientId) {
      return
    }

    setHeaderStatus({ message: 'Connecting Google account...', tone: 'info' })

    try {
      requestGoogleAccessToken(googleClientId, (response) => {
        void handleGoogleTokenResponse(response)
      })
    } catch (error) {
      setHeaderStatus({
        message: getErrorMessage(error, 'Google connection is unavailable'),
        tone: 'error',
      })
    }
  }

  async function handleGoogleTokenResponse(response: {
    access_token?: string
    error?: string
    error_description?: string
  }) {
    if (response.error) {
      setHeaderStatus({
        message: response.error_description ?? 'Google connection was cancelled',
        tone: 'error',
      })
      return
    }

    if (!response.access_token) {
      setHeaderStatus({
        message: 'Google connection did not return an access token',
        tone: 'error',
      })
      return
    }

    try {
      const profile = await fetchGoogleAccountProfile(response.access_token)

      setGoogleAccountConnection({
        status: 'connected',
        accessToken: response.access_token,
        profile,
      })
      setHeaderStatus({ message: 'Google account connected', tone: 'info' })
    } catch (error) {
      setHeaderStatus({
        message: getErrorMessage(error, 'Google profile could not be loaded'),
        tone: 'error',
      })
    }
  }

  function disconnectGoogleAccount() {
    if (googleAccountConnection.status !== 'connected') {
      return
    }

    revokeGoogleAccessToken(googleAccountConnection.accessToken, () => {
      setGoogleAccountConnection({ status: 'disconnected' })
      setHeaderStatus({ message: 'Google account disconnected', tone: 'info' })
    })
  }

  return (
    <main className="flex h-svh min-h-0 flex-col overflow-hidden bg-background text-foreground">
      <header className="shrink-0 border-b border-[#d8d1bd] bg-[#f5f1e6] text-[#252819] shadow-sm">
        <div className="grid h-20 grid-cols-[auto_minmax(0,1fr)_auto] grid-rows-[minmax(0,1fr)_auto] items-center gap-x-2 px-1 pb-2 pt-1 sm:gap-x-4 sm:px-6">
          <div className="relative z-10 col-start-1 row-start-1 self-start justify-self-start whitespace-nowrap text-[clamp(18px,6vw,40px)] font-extrabold leading-none tracking-[-0.08em] text-[#777b60]">
            The Planner
          </div>
          <div className="relative z-10 col-start-1 row-start-2 self-start justify-self-end text-[10px] font-medium leading-none tracking-[0.28em] text-[#8b8f72]">
            v{PRODUCT_VERSION}
          </div>
          <h1 className="relative z-0 col-start-1 col-end-4 row-start-1 min-w-0 whitespace-nowrap text-center text-[clamp(14px,4vw,26px)] font-extrabold tracking-tight">
            <button
              aria-label={`Return to Today, ${formatFullDate(today)}`}
              className="mx-auto block max-w-full truncate rounded-full px-2 py-2 transition-colors hover:bg-[#ebe4d2] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f] focus-visible:ring-offset-2 focus-visible:ring-offset-[#f5f1e6] sm:px-4"
              onClick={jumpToToday}
              title="Return to Today"
              type="button"
            >
              {visibleMonth}
            </button>
          </h1>
          <div className="relative z-10 col-start-3 row-start-1 self-center justify-self-end">
            <AccountControl
              connected={googleAccountConnected}
              disabled={!googleClientId}
              profile={
                googleAccountConnection.status === 'connected'
                  ? googleAccountConnection.profile
                  : null
              }
              onConnect={connectGoogleAccount}
              onDisconnect={disconnectGoogleAccount}
            />
          </div>
          <div
            aria-atomic="true"
            aria-live="polite"
            className={cn(
              'col-start-2 col-end-4 row-start-2 min-h-3 min-w-0 self-start truncate text-right text-[11px] font-medium leading-none',
              effectiveHeaderStatus?.tone === 'error'
                ? 'text-red-700'
                : 'text-[#7c8066]',
            )}
            role="status"
          >
            {effectiveHeaderStatus?.message ?? '\u00A0'}
          </div>
        </div>
        <div className="grid h-10 grid-cols-7 bg-[#e8e2d0] text-xs font-medium uppercase tracking-[0.2em] text-[#6f725a]">
          {WEEKDAY_LABELS.map((weekday, index) => (
            <div
              className={cn(
                'flex items-center justify-center',
                index >= 5 && 'bg-[#ded8c8]/50',
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

                    return (
                      <div
                        key={bar.event.id}
                        className="absolute h-[18px] overflow-hidden truncate pl-4 pr-1 text-[10px] font-medium leading-[18px]"
                        style={{
                          left: `${left}%`,
                          width: `${width}%`,
                          top: `${top}px`,
                          backgroundColor: bar.event.color,
                          color: textColor,
                          borderTopLeftRadius: bar.isStartTruncated ? 0 : 4,
                          borderBottomLeftRadius: bar.isStartTruncated ? 0 : 4,
                          borderTopRightRadius: bar.isEndTruncated ? 0 : 4,
                          borderBottomRightRadius: bar.isEndTruncated ? 0 : 4,
                        }}
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
                              <CellItemRenderer key={i} item={item} />
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
    </main>
  )
}

type AccountControlProps = {
  connected: boolean
  disabled?: boolean
  profile: GoogleAccountProfile | null
  onConnect: () => void
  onDisconnect: () => void
}

function AccountControl({
  connected,
  disabled = false,
  profile,
  onConnect,
  onDisconnect,
}: AccountControlProps) {
  const displayText = connected && profile ? profile.displayName : 'Connect Google'
  const actionLabel = connected
    ? `Disconnect Google account for ${displayText}`
    : 'Connect Google account'
  const ActionIcon = connected ? LogOut : LogIn

  return (
    <button
      aria-label={actionLabel}
      className="inline-flex h-7 w-[62px] items-center justify-center gap-1.5 rounded-full border border-[#d8d1bd] bg-white/80 px-2 text-xs font-medium text-[#384052] shadow-sm transition-colors hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f] focus-visible:ring-offset-2 focus-visible:ring-offset-[#f5f1e6] disabled:cursor-not-allowed disabled:opacity-60 sm:h-8 md:w-48 md:justify-start"
      disabled={disabled}
      onClick={connected ? onDisconnect : onConnect}
      title={actionLabel}
      type="button"
    >
      {connected && profile ? (
        profile.pictureUrl ? (
          <img
            alt={`${profile.displayName} profile`}
            className="-ml-1 h-5 w-5 shrink-0 rounded-full object-cover sm:h-6 sm:w-6"
            src={profile.pictureUrl}
          />
        ) : (
          <span className="-ml-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[#777b60] text-[9px] font-extrabold tracking-[-0.04em] text-white sm:h-6 sm:w-6 sm:text-[10px]">
            {profile.initials}
          </span>
        )
      ) : (
        <span className="-ml-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[#e5e7df] text-[#777b60] sm:h-6 sm:w-6">
          <UserRound aria-hidden="true" className="h-3.5 w-3.5" strokeWidth={2.4} />
        </span>
      )}
      <span className="hidden min-w-0 truncate md:block">{displayText}</span>
      <ActionIcon
        aria-hidden="true"
        className={cn(
          'ml-auto h-4 w-4 shrink-0',
          connected ? 'text-[#384052]' : 'text-[#777b60]',
        )}
        strokeWidth={2.4}
      />
    </button>
  )
}

type CellItemRendererProps = {
  item: import('@/lib/event-layout').CellItem
  weekLayout: import('@/lib/event-layout').WeekLayout
}

function CellItemRenderer({ item }: Omit<CellItemRendererProps, 'weekLayout'>) {
  if (item.kind === 'bar') {
    // Bars are rendered once at the week level; skip here to avoid duplication
    return null
  }

  if (item.kind === 'row') {
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

function getErrorMessage(error: unknown, fallback: string) {
  return error instanceof Error ? error.message : fallback
}

function clamp(value: number, min: number, max: number) {
  return Math.min(Math.max(value, min), max)
}

function prefersReducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches
}
