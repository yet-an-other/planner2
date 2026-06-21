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

    // The dialog is labelled by its title so screen readers announce it.
    const labelledBy = dialog.getAttribute('aria-labelledby')
    expect(labelledBy).toBeTruthy()
    const titleEl = document.getElementById(labelledBy!)
    expect(titleEl).not.toBeNull()
    expect(titleEl!.textContent).toBe('Design Review')

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

describe('EventDetailPopover content', () => {
  it('renders location and description rows when they are present', () => {
    const event = makeRow({
      id: 'evt-loc',
      title: 'Offsite',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
      detail: {
        location: 'Conference Room A',
        description: 'Quarterly planning',
      },
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveTextContent('Conference Room A')
    expect(dialog).toHaveTextContent('Quarterly planning')
  })

  it('omits the location and description rows when they are null', () => {
    const event = makeRow({
      id: 'evt-sparse',
      title: 'Sync',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    const dialog = screen.getByRole('dialog')
    expect(dialog).not.toHaveTextContent('Location')
    expect(dialog).not.toHaveTextContent('Description')
  })

  it('omits the attendees section entirely when the attendee list is empty', () => {
    const event = makeRow({
      id: 'evt-none',
      title: 'Focus block',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    const dialog = screen.getByRole('dialog')
    expect(dialog).not.toHaveTextContent('Attendees')
    expect(dialog).not.toHaveTextContent(/no attendees/i)
  })

  it('renders attendee names with their response status as text', () => {
    const event = makeRow({
      id: 'evt-att',
      title: 'Sync',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
      detail: {
        attendees: [
          { displayName: 'Ada', email: 'ada@example.com', responseStatus: 'accepted' },
          { displayName: 'Bob', email: 'bob@example.com', responseStatus: 'declined' },
        ],
      },
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveTextContent('Ada')
    expect(dialog).toHaveTextContent('accepted')
    expect(dialog).toHaveTextContent('Bob')
    expect(dialog).toHaveTextContent('declined')
  })

  it('falls back to email when an attendee has no display name', () => {
    const event = makeRow({
      id: 'evt-no-name',
      title: 'Sync',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
      detail: {
        attendees: [
          { displayName: null, email: 'stranger@example.com', responseStatus: 'tentative' },
        ],
      },
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    expect(screen.getByText('stranger@example.com')).toBeInTheDocument()
  })

  it('caps attendees at 5 with a "+N more" indicator', () => {
    const event = makeRow({
      id: 'evt-many',
      title: 'All hands',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
      detail: {
        attendees: Array.from({ length: 8 }, (_, i) => ({
          displayName: `Person ${i + 1}`,
          email: `p${i + 1}@example.com`,
          responseStatus: 'accepted' as const,
        })),
      },
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    expect(screen.getByText('Person 1')).toBeInTheDocument()
    expect(screen.getByText('Person 5')).toBeInTheDocument()
    expect(screen.queryByText('Person 6')).not.toBeInTheDocument()
    expect(screen.getByText(/\+3 more/i)).toBeInTheDocument()
  })

  it('renders a long description in a scrollable region', () => {
    const event = makeRow({
      id: 'evt-long',
      title: 'Sync',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
      detail: { description: 'A'.repeat(1000) },
    })

    render(<EventDetailPopover event={event} anchorRect={anchoredRect} onClose={vi.fn()} />)

    const region = screen.getByRole('dialog').querySelector('[data-testid="description"]') as HTMLElement
    expect(region).not.toBeNull()
    expect(region.style.overflowY).toBe('auto')
  })
})

describe('EventDetailPopover placement', () => {
  it('clamps the popover horizontally so a right-edge trigger never overflows', () => {
    const originalWidth = window.innerWidth
    Object.defineProperty(window, 'innerWidth', {
      writable: true,
      configurable: true,
      value: 400,
    })

    const rightEdgeAnchor = {
      ...anchoredRect,
      left: 380,
      right: 400,
      x: 380,
    } as DOMRect
    const event = makeRow({
      id: 'evt-edge',
      title: 'Edge Case',
      date: new Date(2026, 5, 19, 14, 0),
      startTime: '14:00',
    })

    try {
      render(
        <EventDetailPopover event={event} anchorRect={rightEdgeAnchor} onClose={vi.fn()} />,
      )

      const dialog = screen.getByRole('dialog')
      const left = Number.parseInt(dialog.style.left, 10)
      const width = Number.parseInt(dialog.style.width, 10)

      // The popover moved left off the right-edge anchor and stays on screen.
      expect(left).toBeLessThan(380)
      expect(left + width).toBeLessThanOrEqual(window.innerWidth)
    } finally {
      Object.defineProperty(window, 'innerWidth', {
        writable: true,
        configurable: true,
        value: originalWidth,
      })
    }
  })
})
