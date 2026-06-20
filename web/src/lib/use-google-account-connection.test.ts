import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { useGoogleAccountConnection } from './use-google-account-connection'

describe('useGoogleAccountConnection', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
  })

  it('reports a not-configured status when the client id is empty', () => {
    const { result } = renderHook(() => useGoogleAccountConnection(''))

    expect(result.current.isConfigured).toBe(false)
    expect(result.current.status).toEqual({
      message: 'Google client ID is not configured',
      tone: 'error',
    })
    expect(result.current.connection.status).toBe('disconnected')
  })

  it('connects and exposes the access token, profile, and connected status', async () => {
    stubGoogleIdentity({ accessToken: 'access-token' })
    stubProfileFetch({ name: 'Ada Lovelace', picture: 'https://example.com/ada.png' })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))

    await act(async () => {
      result.current.connect()
    })
    await waitFor(() => {
      expect(result.current.connection.status).toBe('connected')
    })

    expect(result.current.connection).toMatchObject({
      accessToken: 'access-token',
      profile: {
        displayName: 'Ada Lovelace',
        pictureUrl: 'https://example.com/ada.png',
      },
    })
    expect(result.current.status).toEqual({
      message: 'Google account connected',
      tone: 'info',
    })
  })

  it('reports a cancelled status and stays disconnected when the token response errors', async () => {
    stubGoogleIdentity({
      error: 'access_denied',
      error_description: 'User denied the request',
    })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))

    await act(async () => {
      result.current.connect()
    })
    await waitFor(() => {
      expect(result.current.status?.tone).toBe('error')
    })

    expect(result.current.status?.message).toBe('User denied the request')
    expect(result.current.connection.status).toBe('disconnected')
  })

  it('disconnects by revoking the token and reports the disconnected status', async () => {
    const revoke = stubGoogleIdentity({ accessToken: 'access-token' })
    stubProfileFetch({ name: 'Ada Lovelace' })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))

    await act(async () => {
      result.current.connect()
    })
    await waitFor(() => expect(result.current.connection.status).toBe('connected'))

    await act(async () => {
      result.current.disconnect()
    })
    await waitFor(() => expect(result.current.connection.status).toBe('disconnected'))

    expect(revoke).toHaveBeenCalledWith('access-token', expect.any(Function))
    expect(result.current.status).toEqual({
      message: 'Google account disconnected',
      tone: 'info',
    })
  })
})

function stubGoogleIdentity(tokenResponse: {
  accessToken?: string
  error?: string
  error_description?: string
}) {
  const revoke = vi.fn((_token: string, done: () => void) => {
    done()
  })
  const requestAccessToken = vi.fn()
  const initTokenClient = vi.fn(({
    callback,
  }: {
    callback: (response: {
      access_token?: string
      error?: string
      error_description?: string
    }) => void
  }) => {
    requestAccessToken.mockImplementation(() => {
      const response: {
        access_token?: string
        error?: string
        error_description?: string
      } = {}
      if (tokenResponse.accessToken) response.access_token = tokenResponse.accessToken
      if (tokenResponse.error) response.error = tokenResponse.error
      if (tokenResponse.error_description)
        response.error_description = tokenResponse.error_description
      callback(response)
    })
    return { requestAccessToken }
  })

  vi.stubGlobal('google', {
    accounts: { oauth2: { initTokenClient, revoke } },
  })

  return revoke
}

function stubProfileFetch(profile: { name: string; picture?: string }) {
  vi.stubGlobal(
    'fetch',
    vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ name: profile.name, picture: profile.picture }),
    }),
  )
}
