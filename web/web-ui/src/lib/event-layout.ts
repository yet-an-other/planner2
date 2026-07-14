import type { CalendarEvent, CalendarEventBar, CalendarEventRow } from './google-calendar-events'

export type BarLayout = {
  event: CalendarEventBar
  laneIndex: number
  startDayIndex: number
  endDayIndex: number
  isStartTruncated: boolean
  isEndTruncated: boolean
}

export type CellItem =
  | { kind: 'bar'; barIndex: number }
  | { kind: 'row'; event: CalendarEventRow }
  | { kind: 'overflow'; count: number }

export type CellLayout = {
  items: CellItem[]
  /**
   * The complete, ordered set of Calendar Events attributed to this cell —
   * bars (lane order) then rows (start time) — uncapped. Source for the
   * Day Events Popover; independent of the visible-cap `items`.
   */
  dayEvents: CalendarEvent[]
}

export type WeekLayout = {
  bars: BarLayout[]
  cells: CellLayout[]
}

export function layoutWeekEvents(events: CalendarEvent[], weekStart: Date): WeekLayout {
  const weekEnd = new Date(weekStart)
  weekEnd.setDate(weekStart.getDate() + 6)

  // Filter and sort bars: start date ascending, then longer duration first
  const barsToPlace = events
    .filter((e): e is CalendarEventBar => e.kind === 'bar')
    .map((bar) => {
      const effectiveStart = bar.date < weekStart ? weekStart : bar.date
      const effectiveEnd = bar.endDate > weekEnd ? weekEnd : bar.endDate
      const startDayIndex = Math.max(0, Math.floor((effectiveStart.getTime() - weekStart.getTime()) / 86_400_000))
      const endDayIndex = Math.min(6, Math.floor((effectiveEnd.getTime() - weekStart.getTime()) / 86_400_000))
      return { bar, effectiveStart, effectiveEnd, startDayIndex, endDayIndex }
    })
    .filter((b) => b.startDayIndex <= b.endDayIndex)
    .sort((a, b) => {
      const startDiff = a.bar.date.getTime() - b.bar.date.getTime()
      if (startDiff !== 0) return startDiff
      const durationA = a.bar.endDate.getTime() - a.bar.date.getTime()
      const durationB = b.bar.endDate.getTime() - b.bar.date.getTime()
      return durationB - durationA // longer first
    })

  const placedBars: BarLayout[] = []

  for (const { bar, startDayIndex, endDayIndex } of barsToPlace) {
    // Find the lowest lane index that doesn't conflict
    let laneIndex = 0
    while (true) {
      const conflict = placedBars.some(
        (pb) =>
          pb.laneIndex === laneIndex &&
          pb.startDayIndex <= endDayIndex &&
          startDayIndex <= pb.endDayIndex,
      )
      if (!conflict) break
      laneIndex++
    }
    placedBars.push({
      event: bar,
      laneIndex,
      startDayIndex,
      endDayIndex,
      isStartTruncated: bar.date < weekStart,
      isEndTruncated: bar.endDate > weekEnd,
    })
  }

  // Collect rows for this week
  const rowsInWeek = events
    .filter((e): e is CalendarEventRow => e.kind === 'row')
    .filter((row) => {
      const rowDate = row.date
      return rowDate >= weekStart && rowDate <= weekEnd
    })
    .sort((a, b) => a.startTime.localeCompare(b.startTime))

  // Build cells from bars and rows, then apply 4-item cap. The pre-cap items
  // are only ever bars or rows (the overflow sentinel is added during capping),
  // so this narrower type lets day-events resolve events without branching.
  type UncappedCellItem =
    | { kind: 'bar'; barIndex: number }
    | { kind: 'row'; event: CalendarEventRow }
  const rawCells: UncappedCellItem[][] = Array.from({ length: 7 }, () => [])
  for (let barIndex = 0; barIndex < placedBars.length; barIndex++) {
    const pb = placedBars[barIndex]
    for (let d = pb.startDayIndex; d <= pb.endDayIndex; d++) {
      rawCells[d].push({ kind: 'bar', barIndex })
    }
  }

  for (const row of rowsInWeek) {
    const dayIndex = Math.floor((row.date.getTime() - weekStart.getTime()) / 86_400_000)
    if (dayIndex >= 0 && dayIndex <= 6) {
      rawCells[dayIndex].push({ kind: 'row', event: row })
    }
  }

  const cells: CellLayout[] = rawCells.map((items) => {
    // The Day Events Popover consumes the full, uncapped, ordered set of
    // events for the cell (bars resolved to their events, then rows).
    const dayEvents: CalendarEvent[] = items.map((item) =>
      item.kind === 'bar' ? placedBars[item.barIndex].event : item.event,
    )
    if (items.length <= 4) {
      return { items, dayEvents }
    }
    const visible: CellItem[] = items.slice(0, 3)
    const overflow = items.length - 3
    visible.push({ kind: 'overflow', count: overflow })
    return { items: visible, dayEvents }
  })

  return { bars: placedBars, cells }
}
