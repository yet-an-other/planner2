import { fireEvent, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { Avatar } from './avatar'

describe('Avatar', () => {
  it('renders the profile image with the picture url and accessible alt text', () => {
    render(
      <Avatar
        displayName="Ada Lovelace"
        initials="AL"
        pictureUrl="https://example.com/ada.png"
        className="h-6 w-6"
      />,
    )

    const img = screen.getByRole('img', { name: /ada lovelace profile/i })
    expect(img).toHaveAttribute('src', 'https://example.com/ada.png')
  })

  it('removes the image and falls back to initials when the picture fails to load', () => {
    render(
      <Avatar
        displayName="Ada Lovelace"
        initials="AL"
        pictureUrl="https://example.com/ada.png"
        className="h-6 w-6"
      />,
    )
    expect(screen.getByText('AL')).toBeInTheDocument()

    fireEvent.error(screen.getByRole('img', { name: /ada lovelace profile/i }))

    // No img remains, so the broken-image placeholder can never show.
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    expect(screen.getByText('AL')).toBeInTheDocument()
  })

  it('reveals the image (not the broken placeholder) once it loads', () => {
    render(
      <Avatar
        displayName="Ada Lovelace"
        initials="AL"
        pictureUrl="https://example.com/ada.png"
        className="h-6 w-6"
      />,
    )
    const img = screen.getByRole('img', { name: /ada lovelace profile/i })
    // Before load the image is kept hidden so initials are what the user sees.
    expect(img.className).toContain('opacity-0')

    fireEvent.load(img)

    expect(screen.getByRole('img', { name: /ada lovelace profile/i }).className).toContain(
      'opacity-100',
    )
  })

  it('shows initials and no image when there is no picture url', () => {
    render(
      <Avatar
        displayName="Ada"
        initials="A"
        pictureUrl={null}
        className="h-6 w-6"
      />,
    )

    expect(screen.getByText('A')).toBeInTheDocument()
    expect(screen.queryByRole('img')).not.toBeInTheDocument()
  })

  it('attempts to load a new image when the picture url changes', () => {
    const { rerender } = render(
      <Avatar
        displayName="Ada Lovelace"
        initials="AL"
        pictureUrl="https://example.com/ada.png"
        className="h-6 w-6"
      />,
    )
    // First image fails.
    fireEvent.error(screen.getByRole('img', { name: /ada lovelace profile/i }))
    expect(screen.queryByRole('img')).not.toBeInTheDocument()

    // A new url is provided (e.g. profile refreshed).
    rerender(
      <Avatar
        displayName="Ada Lovelace"
        initials="AL"
        pictureUrl="https://example.com/ada2.png"
        className="h-6 w-6"
      />,
    )

    expect(screen.getByRole('img', { name: /ada lovelace profile/i })).toHaveAttribute(
      'src',
      'https://example.com/ada2.png',
    )
  })
})
