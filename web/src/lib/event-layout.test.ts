import { describe, expect, it } from 'vitest'
import type { CalendarEventBar, CalendarEventRow } from './google-calendar-events'
import { layoutWeekEvents } from './event-layout'

function mondayOf(dateStr: string) {
  const date = new Date(dateStr)
  const day = date.getDay()
  const diff = (day + 6) % 7
  const monday = new Date(date)
  monday.setDate(date.getDate() - diff)
  return new Date(monday.getFullYear(), monday.getMonth(), monday.getDate())
}

describe('layoutWeekEvents', () => {
  it('returns an empty layout when no events are provided', () => {
    const weekStart = mondayOf('2026-06-15')

    const layout = layoutWeekEvents([], weekStart)

    expect(layout.bars).toEqual([])
    expect(layout.cells).toHaveLength(7)
    for (const cell of layout.cells) {
      expect(cell.items).toEqual([])
    }
  })

  it('places a single all-day bar on Monday in lane 0', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar: CalendarEventBar = {
      kind: 'bar',
      eventType: 'all-day',
      id: 'evt-1',
      title: 'Team Lunch',
      date: new Date(2026, 5, 15),
      endDate: new Date(2026, 5, 15),
      color: '#2952a3',
    }

    const layout = layoutWeekEvents([bar], weekStart)

    expect(layout.bars).toHaveLength(1)
    expect(layout.bars[0]).toMatchObject({
      laneIndex: 0,
      startDayIndex: 0,
      endDayIndex: 0,
    })
    expect(layout.bars[0].event.title).toBe('Team Lunch')

    expect(layout.cells[0].items).toEqual([])
    for (let i = 1; i < 7; i++) {
      expect(layout.cells[i].items).toEqual([])
    }
  })

  it('places a multiday bar spanning Monday to Wednesday', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar: CalendarEventBar = {
      kind: 'bar',
      eventType: 'multiday',
      id: 'evt-2',
      title: 'Q3 Planning',
      date: new Date(2026, 5, 15), // Mon
      endDate: new Date(2026, 5, 17), // Wed
      color: '#2952a3',
    }

    const layout = layoutWeekEvents([bar], weekStart)

    expect(layout.bars).toHaveLength(1)
    expect(layout.bars[0]).toMatchObject({
      laneIndex: 0,
      startDayIndex: 0,
      endDayIndex: 2,
    })

    expect(layout.cells[0].items).toEqual([])
    expect(layout.cells[1].items).toEqual([])
    expect(layout.cells[2].items).toEqual([])
    expect(layout.cells[3].items).toEqual([])
  })

  it('stacks overlapping multiday bars in separate vertical lanes', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar1: CalendarEventBar = {
      kind: 'bar',
      eventType: 'multiday',
      id: 'evt-3',
      title: 'Team Offsite',
      date: new Date(2026, 5, 15), // Mon
      endDate: new Date(2026, 5, 17), // Wed
      color: '#2952a3',
    }
    const bar2: CalendarEventBar = {
      kind: 'bar',
      eventType: 'multiday',
      id: 'evt-4',
      title: 'Sprint Planning',
      date: new Date(2026, 5, 15), // Mon
      endDate: new Date(2026, 5, 19), // Fri
      color: '#0d7377',
    }

    const layout = layoutWeekEvents([bar1, bar2], weekStart)

    expect(layout.bars).toHaveLength(2)
    // Sprint Planning is longer → sorts first, gets lane 0
    // Team Offsite is shorter → sorts second, gets lane 1
    expect(layout.bars[0].event.title).toBe('Sprint Planning')
    expect(layout.bars[0].laneIndex).toBe(0)
    expect(layout.bars[1].event.title).toBe('Team Offsite')
    expect(layout.bars[1].laneIndex).toBe(1)

    // Bars no longer appear in cell items — only rows and overflow do
    expect(layout.cells[0].items).toEqual([])
    expect(layout.cells[1].items).toEqual([])
    expect(layout.cells[2].items).toEqual([])
    expect(layout.cells[3].items).toEqual([])
    expect(layout.cells[4].items).toEqual([])
  })

  it('places rows below the overlay bars', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar: CalendarEventBar = {
      kind: 'bar',
      eventType: 'all-day',
      id: 'evt-5',
      title: 'All-hands',
      date: new Date(2026, 5, 17), // Wed
      endDate: new Date(2026, 5, 17), // Wed
      color: '#2952a3',
    }
    const row: CalendarEventRow = {
      kind: 'row',
      id: 'evt-6',
      title: 'Design Review',
      date: new Date(2026, 5, 17), // Wed
      startTime: '14:00',
      durationMinutes: 60,
      color: '#0d7377',
    }

    const layout = layoutWeekEvents([bar, row], weekStart)

    expect(layout.bars).toHaveLength(1)
    expect(layout.bars[0].laneIndex).toBe(0)

    // Wed (index 2) — only the row appears in the cell items
    expect(layout.cells[2].items).toEqual([
      { kind: 'row', event: row },
    ])
  })

  it('caps visible rows per cell to 4, with overflow replacing the 4th slot', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar: CalendarEventBar = {
      kind: 'bar',
      eventType: 'all-day',
      id: 'evt-b',
      title: 'All-hands',
      date: new Date(2026, 5, 15), // Mon
      endDate: new Date(2026, 5, 15), // Mon
      color: '#2952a3',
    }
    const rows: CalendarEventRow[] = Array.from({ length: 6 }, (_, i) => ({
      kind: 'row' as const,
      id: `evt-r-${i}`,
      title: `Meeting ${i + 1}`,
      date: new Date(2026, 5, 15), // Mon
      startTime: `${9 + i}:00`,
      durationMinutes: 60,
      color: '#0d7377',
    }))

    const layout = layoutWeekEvents([bar, ...rows], weekStart)

    // Mon (index 0): 6 rows → capped to 3 rows + overflow
    expect(layout.cells[0].items).toHaveLength(4)
    expect(layout.cells[0].items[0]).toMatchObject({ kind: 'row' })
    expect(layout.cells[0].items[1]).toMatchObject({ kind: 'row' })
    expect(layout.cells[0].items[2]).toMatchObject({ kind: 'row' })
    expect(layout.cells[0].items[3]).toEqual({ kind: 'overflow', count: 3 })
  })

  it('orders intraday rows by start time within a cell', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const rows: CalendarEventRow[] = [
      {
        kind: 'row',
        id: 'evt-late',
        title: 'Late Meeting',
        date: new Date(2026, 5, 15), // Mon
        startTime: '16:00',
        durationMinutes: 60,
        color: '#0d7377',
      },
      {
        kind: 'row',
        id: 'evt-early',
        title: 'Early Standup',
        date: new Date(2026, 5, 15), // Mon
        startTime: '09:00',
        durationMinutes: 30,
        color: '#2952a3',
      },
    ]

    const layout = layoutWeekEvents(rows, weekStart)

    expect(layout.cells[0].items).toHaveLength(2)
    expect(layout.cells[0].items[0]).toMatchObject({
      kind: 'row',
      event: { title: 'Early Standup' },
    })
    expect(layout.cells[0].items[1]).toMatchObject({
      kind: 'row',
      event: { title: 'Late Meeting' },
    })
  })

  it('shows a bar that started before the week and ends during the week', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar: CalendarEventBar = {
      kind: 'bar',
      eventType: 'multiday',
      id: 'evt-7',
      title: 'Conference',
      date: new Date(2026, 5, 13), // Sat (before week)
      endDate: new Date(2026, 5, 17), // Wed
      color: '#2952a3',
    }

    const layout = layoutWeekEvents([bar], weekStart)

    expect(layout.bars).toHaveLength(1)
    expect(layout.bars[0]).toMatchObject({
      laneIndex: 0,
      startDayIndex: 0, // starts Monday (first visible day)
      endDayIndex: 2,   // ends Wednesday
    })

    // Only Mon, Tue, Wed have the bar
    expect(layout.cells[0].items).toEqual([])
    expect(layout.cells[1].items).toEqual([])
    expect(layout.cells[2].items).toEqual([])
    expect(layout.cells[3].items).toEqual([])
  })

  it('marks bars as truncated when clipped by week boundaries', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar: CalendarEventBar = {
      kind: 'bar',
      eventType: 'multiday',
      id: 'evt-8',
      title: 'Conference',
      date: new Date(2026, 5, 12), // Fri before week
      endDate: new Date(2026, 5, 23), // Wed after week
      color: '#2952a3',
    }

    const layout = layoutWeekEvents([bar], weekStart)

    expect(layout.bars[0].startDayIndex).toBe(0)
    expect(layout.bars[0].endDayIndex).toBe(6)
    expect(layout.bars[0].isStartTruncated).toBe(true)
    expect(layout.bars[0].isEndTruncated).toBe(true)
  })

  it('does not mark bars as truncated when they start and end within the week', () => {
    const weekStart = mondayOf('2026-06-15') // Mon, Jun 15
    const bar: CalendarEventBar = {
      kind: 'bar',
      eventType: 'multiday',
      id: 'evt-9',
      title: 'Workshop',
      date: new Date(2026, 5, 16), // Tue
      endDate: new Date(2026, 5, 18), // Thu
      color: '#2952a3',
    }

    const layout = layoutWeekEvents([bar], weekStart)

    expect(layout.bars[0].startDayIndex).toBe(1)
    expect(layout.bars[0].endDayIndex).toBe(3)
    expect(layout.bars[0].isStartTruncated).toBe(false)
    expect(layout.bars[0].isEndTruncated).toBe(false)
  })
})
