import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it, vi } from 'vitest'
import { SourceCalendarPicker } from '@/components/source-calendar-picker'
import type { SourceCalendar } from '@/lib/google-calendar-events'

const calendars: SourceCalendar[] = [
  { id: 'work', summary: 'Work', backgroundColor: '#ff0000', primary: false },
  {
    id: 'primary',
    summary: 'My Calendar',
    backgroundColor: '#2952a3',
    primary: true,
  },
  { id: 'family', summary: 'Family', backgroundColor: '#16a34a', primary: false },
]

describe('SourceCalendarPicker', () => {
  it('lists the calendars with the primary calendar first and badged', () => {
    render(
      <SourceCalendarPicker
        available={calendars}
        selectedIds={['primary']}
        onSave={vi.fn()}
        onCancel={vi.fn()}
      />,
    )

    const checkboxes = screen.getAllByRole('checkbox')
    expect(checkboxes).toHaveLength(3)
    // Primary calendar is ordered first.
    expect(checkboxes[0]).toHaveAccessibleName(/my calendar/i)
    expect(screen.getByText('Primary')).toBeInTheDocument() // the badge
  })

  it('toggles a calendar into the draft and applies it on Save', () => {
    const onSave = vi.fn()
    render(
      <SourceCalendarPicker
        available={calendars}
        selectedIds={['primary']}
        onSave={onSave}
        onCancel={vi.fn()}
      />,
    )

    const work = screen.getByRole('checkbox', { name: /work/i })
    expect(work).not.toBeChecked()
    fireEvent.click(work)
    expect(work).toBeChecked()

    fireEvent.click(screen.getByRole('button', { name: /save/i }))
    expect(onSave).toHaveBeenCalledTimes(1)
    expect(onSave.mock.calls[0][0]).toEqual(['primary', 'work'])
  })

  it('disables Save when the draft would select zero calendars (minimum-one)', () => {
    render(
      <SourceCalendarPicker
        available={calendars}
        selectedIds={['primary']}
        onSave={vi.fn()}
        onCancel={vi.fn()}
      />,
    )

    const save = screen.getByRole('button', { name: /save/i })
    expect(save).not.toBeDisabled()

    fireEvent.click(screen.getByRole('checkbox', { name: /my calendar/i }))
    expect(save).toBeDisabled()
  })

  it('discards the draft on Cancel without saving', () => {
    const onSave = vi.fn()
    const onCancel = vi.fn()
    render(
      <SourceCalendarPicker
        available={calendars}
        selectedIds={['primary']}
        onSave={onSave}
        onCancel={onCancel}
      />,
    )

    fireEvent.click(screen.getByRole('checkbox', { name: /work/i }))
    fireEvent.click(screen.getByRole('button', { name: /cancel/i }))

    expect(onCancel).toHaveBeenCalledTimes(1)
    expect(onSave).not.toHaveBeenCalled()
  })

  it('Select all checks every calendar', () => {
    render(
      <SourceCalendarPicker
        available={calendars}
        selectedIds={['primary']}
        onSave={vi.fn()}
        onCancel={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: /select all/i }))

    for (const checkbox of screen.getAllByRole('checkbox')) {
      expect(checkbox).toBeChecked()
    }
  })

  it('Reset to primary selects only the primary calendar, obeying minimum-one', () => {
    render(
      <SourceCalendarPicker
        available={calendars}
        selectedIds={['work', 'primary', 'family']}
        onSave={vi.fn()}
        onCancel={vi.fn()}
      />,
    )

    fireEvent.click(screen.getByRole('button', { name: /reset to primary/i }))

    const checked = screen
      .getAllByRole('checkbox')
      .filter((c) => (c as HTMLInputElement).checked)
    expect(checked).toHaveLength(1)
    expect(screen.getByRole('checkbox', { name: /my calendar/i })).toBeChecked()
    expect(screen.getByRole('checkbox', { name: /work/i })).not.toBeChecked()
    expect(screen.getByRole('checkbox', { name: /family/i })).not.toBeChecked()
  })

  it('closes (discards) on Escape', () => {
    const onSave = vi.fn()
    const onCancel = vi.fn()
    render(
      <SourceCalendarPicker
        available={calendars}
        selectedIds={['primary']}
        onSave={onSave}
        onCancel={onCancel}
      />,
    )

    fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' })

    expect(onCancel).toHaveBeenCalledTimes(1)
    expect(onSave).not.toHaveBeenCalled()
  })
})
