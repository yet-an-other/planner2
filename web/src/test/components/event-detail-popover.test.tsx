import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { EventDetailPopover } from '@/components/event-detail-popover'
import { makeRow } from '../lib/calendar-events.factory'

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

describe('EventDetailPopover', () => {
  it('renders nothing when there is no event', () => {
    const { container } = render(
      <EventDetailPopover event={null} anchorRect={anchoredRect} onClose={vi.fn()} />,
    )

    expect(container).toBeEmptyDOMElement()
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('renders the title, timing, and an external Google Calendar link for a row event', () => {
    const event = makeRow({
      id: 'evt-1',
      title: 'Design Review',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
      htmlLink: 'https://www.google.com/calendar/event?eid=evt-1',
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveAttribute('aria-modal', 'false')
    expect(dialog).toHaveTextContent('Design Review')
    expect(dialog).toHaveTextContent('Fri, Jun 19, 2026')

    const link = screen.getByRole('link', { name: /open in google calendar/i })
    expect(link).toHaveAttribute(
      'href',
      'https://www.google.com/calendar/event?eid=evt-1',
    )
    expect(link).toHaveAttribute('target', '_blank')
    expect(link).toHaveAttribute('rel', 'noopener noreferrer')
  })

  it('omits the Google Calendar link when the event has no htmlLink', () => {
    const event = makeRow({
      id: 'evt-2',
      title: 'No link',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    expect(
      screen.queryByRole('link', { name: /open in google calendar/i }),
    ).not.toBeInTheDocument()
  })

  it('renders through a portal outside the render container, fixed-positioned from the anchor rect', () => {
    const event = makeRow({
      id: 'evt-3',
      title: 'Sync',
      date: new Date(2026, 5, 19, 9, 0),
      startTime: '09:00',
    })

    const { container } = render(
      <EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />,
    )

    // The dialog is portaled to document.body, not inside the render container.
    expect(container.querySelector('[role="dialog"]')).toBeNull()
    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveStyle({ position: 'fixed' })
  })

  it('closes when the close button is clicked', () => {
    const onClose = vi.fn()
    const event = makeRow({
      id: 'evt-4',
      title: 'Sync',
      date: new Date(2026, 5, 19, 9, 0),
      startTime: '09:00',
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={onClose} />)

    fireEvent.click(screen.getByRole('button', { name: /close/i }))

    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('closes when Escape is pressed inside the dialog', () => {
    const onClose = vi.fn()
    const event = makeRow({
      id: 'evt-5',
      title: 'Sync',
      date: new Date(2026, 5, 19, 9, 0),
      startTime: '09:00',
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={onClose} />)

    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' })

    expect(onClose).toHaveBeenCalledTimes(1)
  })
})
