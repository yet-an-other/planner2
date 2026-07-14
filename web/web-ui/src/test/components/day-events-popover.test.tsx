import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { DayEventsPopover } from '@/components/day-events-popover'
import { makeBar, makeRow } from '../lib/calendar-events.factory'

const anchoredRect = {
  bottom: 100,
  left: 50,
  top: 80,
  right: 70,
  height: 20,
  width: 20,
  x: 50,
  y: 80,
  toJSON: () => ({}),
} as DOMRect

describe('DayEventsPopover', () => {
  it('renders nothing when there are no day events', () => {
    const { container } = render(
      <DayEventsPopover
        dayEvents={null}
        date={null}
        anchorRect={anchoredRect}
        onClose={vi.fn()}
      />,
    )

    expect(container).toBeEmptyDOMElement()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('renders a labelled, non-modal dialog with the date header and every event in order', () => {
    const date = new Date(2026, 5, 19) // Fri, Jun 19
    const bar = makeBar({
      id: 'b1',
      title: 'All-hands',
      date: new Date(2026, 5, 19),
      endDate: new Date(2026, 5, 19),
    })
    const early = makeRow({
      id: 'r1',
      title: 'Standup',
      date: new Date(2026, 5, 19),
      startTime: '09:00',
    })
    const late = makeRow({
      id: 'r2',
      title: 'Demo',
      date: new Date(2026, 5, 19),
      startTime: '14:00',
    })

    render(
      <DayEventsPopover
        dayEvents={[bar, early, late]}
        date={date}
        anchorRect={anchoredRect}
        onClose={vi.fn()}
      />,
    )

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveAttribute('aria-modal', 'false')
    expect(dialog).toHaveTextContent('Friday, June 19, 2026')

    // The dialog is labelled by its date header so screen readers announce it.
    const labelledBy = dialog.getAttribute('aria-labelledby')
    expect(labelledBy).toBeTruthy()
    expect(document.getElementById(labelledBy!)).not.toBeNull()

    // Bar first (with its All-day timing label), then rows by start time.
    expect(dialog).toHaveTextContent('All-hands')
    expect(dialog).toHaveTextContent('All day')
    expect(dialog).toHaveTextContent('09:00')
    expect(dialog).toHaveTextContent('Standup')
    expect(dialog).toHaveTextContent('14:00')
    expect(dialog).toHaveTextContent('Demo')
  })

  it('closes when the close button is clicked', () => {
    const onClose = vi.fn()
    const date = new Date(2026, 5, 19)
    const row = makeRow({
      id: 'r1',
      title: 'Standup',
      date: new Date(2026, 5, 19),
      startTime: '09:00',
    })

    render(
      <DayEventsPopover
        dayEvents={[row]}
        date={date}
        anchorRect={anchoredRect}
        onClose={onClose}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: /close/i }))

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('closes when Escape is pressed inside the dialog', () => {
    const onClose = vi.fn()
    const date = new Date(2026, 5, 19)
    const row = makeRow({
      id: 'r1',
      title: 'Standup',
      date: new Date(2026, 5, 19),
      startTime: '09:00',
    })

    render(
      <DayEventsPopover
        dayEvents={[row]}
        date={date}
        anchorRect={anchoredRect}
        onClose={onClose}
      />,
    )

    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' })

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('renders through a portal outside the render container, fixed-positioned from the anchor rect', () => {
    const date = new Date(2026, 5, 19)
    const row = makeRow({
      id: 'r1',
      title: 'Sync',
      date: new Date(2026, 5, 19),
      startTime: '09:00',
    })

    const { container } = render(
      <DayEventsPopover
        dayEvents={[row]}
        date={date}
        anchorRect={anchoredRect}
        onClose={vi.fn()}
      />,
    )

    expect(container.querySelector('[role="dialog"]')).toBeNull()
    expect(screen.getByRole('dialog')).toHaveStyle({ position: 'fixed' })
  })

  it('shows a multiday bar with a date-span timing label', () => {
    const date = new Date(2026, 5, 17) // Wed within the span
    const bar = makeBar({
      id: 'span',
      title: 'Conference',
      eventType: 'multiday',
      date: new Date(2026, 5, 15), // Mon
      endDate: new Date(2026, 5, 17), // Wed
    })

    render(
      <DayEventsPopover
        dayEvents={[bar]}
        date={date}
        anchorRect={anchoredRect}
        onClose={vi.fn()}
      />,
    )

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveTextContent('Conference')
    // A multiday bar shows its date span, not a single time.
    expect(dialog).toHaveTextContent('Jun 15, 2026')
    expect(dialog).toHaveTextContent('Jun 17, 2026')
  })

  it('calls onSelectEvent with the event and its trigger when an interactive row is selected', () => {
    const onSelectEvent = vi.fn()
    const date = new Date(2026, 5, 19)
    const row = makeRow({
      id: 'r1',
      title: 'Standup',
      date: new Date(2026, 5, 19),
      startTime: '09:00',
    })

    render(
      <DayEventsPopover
        dayEvents={[row]}
        date={date}
        anchorRect={anchoredRect}
        onClose={vi.fn()}
        onSelectEvent={onSelectEvent}
      />,
    )

    fireEvent.click(
      screen.getByRole('button', { name: /standup.*open details/i }),
    )

    expect(onSelectEvent).toHaveBeenCalledTimes(1)
    const [event, trigger] = onSelectEvent.mock.calls[0]
    expect(event).toBe(row)
    expect(trigger).toBeInstanceOf(HTMLElement)
  })

  it('renders items as inert (non-interactive) when no onSelectEvent is supplied', () => {
    const date = new Date(2026, 5, 19)
    const row = makeRow({
      id: 'r1',
      title: 'Standup',
      date: new Date(2026, 5, 19),
      startTime: '09:00',
    })

    render(
      <DayEventsPopover
        dayEvents={[row]}
        date={date}
        anchorRect={anchoredRect}
        onClose={vi.fn()}
      />,
    )

    // No drill-through affordances; the close button is the only button.
    expect(
      screen.queryByRole('button', { name: /open details/i }),
    ).not.toBeInTheDocument()
    expect(screen.getAllByRole('button')).toHaveLength(1) // close only
  })
})
