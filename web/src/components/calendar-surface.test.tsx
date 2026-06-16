import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { CalendarSurface } from './calendar-surface'

describe('Google Account Connection', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', '')
  })

  it('tells the user when Google Account Connection is not configured', () => {
    render(<CalendarSurface />)

    expect(
      screen.getByRole('button', { name: /connect google account/i }),
    ).toBeDisabled()
    expect(screen.getByRole('status')).toHaveTextContent(
      'Google client ID is not configured',
    )
  })

  it('connects a Google Account and displays the real profile', async () => {
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    const user = userEvent.setup()
    stubSuccessfulGoogleConnection()

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))

    expect(await screen.findByText('Ada Lovelace')).toBeInTheDocument()
    expect(screen.getByRole('img', { name: /Ada Lovelace/i })).toHaveAttribute(
      'src',
      'https://example.com/ada.png',
    )
    expect(screen.getByRole('status')).toHaveTextContent(
      'Google account connected',
    )
  })

  it('disconnects a Google Account by revoking the current access token', async () => {
    vi.stubEnv('VITE_GOOGLE_CLIENT_ID', 'test-client-id')
    const user = userEvent.setup()
    const { revoke } = stubSuccessfulGoogleConnection()

    render(<CalendarSurface />)

    await user.click(screen.getByRole('button', { name: /connect google/i }))
    await screen.findByText('Ada Lovelace')
    await user.click(
      screen.getByRole('button', {
        name: /disconnect google account for ada lovelace/i,
      }),
    )

    expect(revoke).toHaveBeenCalledWith('access-token', expect.any(Function))
    expect(
      screen.getByRole('button', { name: /connect google account/i }),
    ).toBeInTheDocument()
    expect(screen.getByRole('status')).toHaveTextContent(
      'Google account disconnected',
    )
  })
})

function stubSuccessfulGoogleConnection() {
  const requestAccessToken = vi.fn()
  const revoke = vi.fn((_accessToken: string, done: () => void) => {
    done()
  })
  const initTokenClient = vi.fn(({ callback }) => {
    requestAccessToken.mockImplementation(() => {
      callback({ access_token: 'access-token' })
    })

    return { requestAccessToken }
  })

  vi.stubGlobal('google', {
    accounts: {
      oauth2: {
        initTokenClient,
        revoke,
      },
    },
  })
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        name: 'Ada Lovelace',
        picture: 'https://example.com/ada.png',
      }),
    }),
  )

  return { revoke }
}
