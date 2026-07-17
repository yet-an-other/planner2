import { act, renderHook, waitFor } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { GoogleAccountProfile } from '@planner/web-contracts'
import { useGoogleAccountConnection } from '@/lib/use-google-account-connection'

const PROFILE: GoogleAccountProfile = {
  email: 'ada@example.com',
  displayName: 'Ada Lovelace',
  initials: 'AL',
  pictureUrl: 'https://example.com/ada.png',
}

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

  it('connects via the backend in a single round-trip: code -> POST /api/auth/callback', async () => {
    const { requestCode, getCodeClientConfig } = stubCodeIdentity({ code: 'the-code' })
    const fetchMock = stubBackend({
      profile: PROFILE,
      accessToken: 'access-token',
      hasSession: false,
    })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))

    await act(async () => {
      result.current.connect()
    })
    await waitFor(() => {
      expect(result.current.connection.status).toBe('connected')
    })

    // The code client must request offline access + consent so Google issues a refresh token.
    expect(getCodeClientConfig()).toMatchObject({
      access_type: 'offline',
      prompt: 'consent',
    })
    expect(requestCode).toHaveBeenCalled()
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/auth/callback',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ code: 'the-code' }),
      }),
    )

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

  it('reports a cancelled status and stays disconnected when the code response errors', async () => {
    stubCodeIdentity({
      error: 'access_denied',
      error_description: 'User denied the request',
    })
    stubBackend({ profile: PROFILE, accessToken: 'access-token', hasSession: false })
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

  it('disconnects via DELETE /api/connection only after the request succeeds', async () => {
    stubCodeIdentity({ code: 'the-code' })
    const fetchMock = stubBackend({
      profile: PROFILE,
      accessToken: 'access-token',
      hasSession: false,
    })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))

    await act(async () => {
      result.current.connect()
    })
    await waitFor(() => expect(result.current.connection.status).toBe('connected'))

    await act(async () => {
      result.current.disconnect()
    })
    await waitFor(() => expect(result.current.connection.status).toBe('disconnected'))

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/connection',
      expect.objectContaining({ method: 'DELETE' }),
    )
    expect(result.current.status).toEqual({
      message: 'Google account disconnected on this device',
      tone: 'info',
    })
  })

  it('stays connected and reports an actionable error when local deletion fails', async () => {
    stubCodeIdentity({ code: 'the-code' })
    stubBackend({
      profile: PROFILE,
      accessToken: 'access-token',
      hasSession: false,
      connectionDeleteSucceeds: false,
    })
    const { result } = renderHook(() =>
      useGoogleAccountConnection('test-client-id'),
    )

    await act(async () => {
      result.current.connect()
    })
    await waitFor(() => expect(result.current.connection.status).toBe('connected'))

    await act(async () => {
      await expect(result.current.disconnect()).rejects.toThrow(
        'Google connection could not be removed from this device',
      )
    })

    expect(result.current.connection.status).toBe('connected')
    expect(result.current.status).toEqual({
      message: 'Could not disconnect Google account on this device. Try again',
      tone: 'error',
    })
  })

  it('silently restores the connection from /api/token on mount', async () => {
    const fetchMock = stubBackend({
      profile: PROFILE,
      accessToken: 'restored-token',
      hasSession: true,
    })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))

    await waitFor(() => {
      expect(result.current.connection.status).toBe('connected')
    })

    expect(result.current.connection).toMatchObject({
      accessToken: 'restored-token',
      profile: { displayName: 'Ada Lovelace' },
    })
    // No GIS code-client flow ran on a silent restore.
    expect(fetchMock).not.toHaveBeenCalledWith(
      '/api/auth/callback',
      expect.anything(),
    )
  })

  it('stays disconnected (not an error) on mount when there is no session', async () => {
    const fetchMock = stubBackend({
      profile: PROFILE,
      accessToken: 'access-token',
      hasSession: false,
    })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))

    await waitFor(() => {
      expect(fetchMock).toHaveBeenCalledWith('/api/token')
      expect(result.current.status).toBe(null)
    })

    expect(result.current.connection.status).toBe('disconnected')
    expect(result.current.status?.tone).not.toBe('error')
  })

  it('refreshAccessToken reads /api/token and returns the fresh token', async () => {
    const fetchMock = stubBackend({
      profile: PROFILE,
      accessToken: 'fresh-token',
      hasSession: true,
    })
    const { result } = renderHook(() => useGoogleAccountConnection('test-client-id'))
    await waitFor(() => expect(result.current.connection.status).toBe('connected'))

    const before = fetchMock.mock.calls.filter(
      (call) => String(call[0]) === '/api/token',
    ).length
    let token = ''
    await act(async () => {
      token = await result.current.refreshAccessToken()
    })
    const after = fetchMock.mock.calls.filter(
      (call) => String(call[0]) === '/api/token',
    ).length

    expect(token).toBe('fresh-token')
    expect(after).toBe(before + 1)
  })

  it('disconnects gracefully when refreshAccessToken finds the session revoked (401)', async () => {
    stubCodeIdentity({ code: 'the-code' })
    stubBackend({
      profile: PROFILE,
      accessToken: 'access-token',
      hasSession: false,
    })
    const { result } = renderHook(
      () => useGoogleAccountConnection('test-client-id'),
    )

    await act(async () => {
      result.current.connect()
    })
    await waitFor(() =>
      expect(result.current.connection.status).toBe('connected'),
    )

    // /api/token is 401 (hasSession: false) -> the grant is gone; refreshAccessToken
    // must disconnect rather than leave a stale connected state.
    await act(async () => {
      await expect(result.current.refreshAccessToken()).rejects.toBeDefined()
    })

    expect(result.current.connection.status).toBe('disconnected')
  })
})

describe('tab independence (no cross-tab synchronization)', () => {
  beforeEach(() => {
    vi.unstubAllEnvs()
    vi.unstubAllGlobals()
  })

  it('does not affect a sibling tab when one tab disconnects', async () => {
    const backend = stubSharedBackend({ profile: PROFILE, initiallyConnected: true })

    const tabA = renderHook(() => useGoogleAccountConnection('test-client-id'))
    const tabB = renderHook(() => useGoogleAccountConnection('test-client-id'))
    await waitFor(() => expect(tabA.result.current.connection.status).toBe('connected'))
    await waitFor(() => expect(tabB.result.current.connection.status).toBe('connected'))

    await act(async () => {
      await tabA.result.current.disconnect()
    })

    expect(tabA.result.current.connection.status).toBe('disconnected')
    // Tab B has made no request of its own since Tab A's disconnect, so it
    // keeps showing connected from its own in-memory state — there is no
    // broadcast that reaches it.
    expect(tabB.result.current.connection.status).toBe('connected')
    expect(backend.hasSession()).toBe(false)

    // Only once Tab B makes its own request does it discover the cleared
    // session, via the same ordinary 401 path used for a revoked grant.
    await act(async () => {
      await expect(tabB.result.current.refreshAccessToken()).rejects.toBeDefined()
    })
    expect(tabB.result.current.connection.status).toBe('disconnected')
  })

  it('does not affect a sibling tab when one tab connects', async () => {
    const backend = stubSharedBackend({ profile: PROFILE, initiallyConnected: false })
    stubCodeIdentity({ code: 'the-code' })

    const tabA = renderHook(() => useGoogleAccountConnection('test-client-id'))
    const tabB = renderHook(() => useGoogleAccountConnection('test-client-id'))
    await waitFor(() => expect(tabA.result.current.connection.status).toBe('disconnected'))
    await waitFor(() => expect(tabB.result.current.connection.status).toBe('disconnected'))

    await act(async () => {
      tabA.result.current.connect()
    })
    await waitFor(() => expect(tabA.result.current.connection.status).toBe('connected'))

    // Tab B never called connect and never restored again, so it remains
    // disconnected in its own state — there is no broadcast that reaches it.
    expect(tabB.result.current.connection.status).toBe('disconnected')
    expect(backend.hasSession()).toBe(true)
  })

  it('keeps two simulated browser profiles fully isolated', async () => {
    stubProfileFetch({ profile: PROFILE, hasSession: true })
    const { result: tabInProfileOne } = renderHook(() =>
      useGoogleAccountConnection('test-client-id'),
    )
    await waitFor(() =>
      expect(tabInProfileOne.current.connection.status).toBe('connected'),
    )
    await act(async () => {
      await tabInProfileOne.current.disconnect()
    })
    expect(tabInProfileOne.current.connection.status).toBe('disconnected')

    // A second, independent browser profile (its own mocked backend/cookie
    // jar) is entirely unaffected by the first profile's disconnect.
    const otherProfile = {
      email: 'grace@example.com',
      displayName: 'Grace Hopper',
      initials: 'GH',
      pictureUrl: 'https://example.com/grace.png',
    }
    stubProfileFetch({ profile: otherProfile, hasSession: true })
    const { result: tabInProfileTwo } = renderHook(() =>
      useGoogleAccountConnection('test-client-id'),
    )
    await waitFor(() =>
      expect(tabInProfileTwo.current.connection.status).toBe('connected'),
    )
    expect(tabInProfileTwo.current.connection).toMatchObject({
      profile: { displayName: 'Grace Hopper' },
    })
  })
})

type CodeResponse = {
  code?: string
  error?: string
  error_description?: string
}

function stubCodeIdentity(codeResponse: CodeResponse) {
  let codeClientConfig: Record<string, unknown> = {}
  const requestCode = vi.fn()
  const initCodeClient = vi.fn((config: Record<string, unknown>) => {
    codeClientConfig = config
    const callback = config.callback as (response: CodeResponse) => void
    requestCode.mockImplementation(() => callback(codeResponse))
    return { requestCode }
  })

  vi.stubGlobal('google', {
    accounts: { oauth2: { initCodeClient } },
  })

  return { requestCode, getCodeClientConfig: () => codeClientConfig }
}

function stubBackend({
  profile,
  accessToken,
  hasSession,
  connectionDeleteSucceeds = true,
}: {
  profile: GoogleAccountProfile
  accessToken: string
  hasSession: boolean
  connectionDeleteSucceeds?: boolean
}) {
  const fetchMock = vi.fn(async (url: string) => {
    if (url === '/api/auth/callback') {
      return { ok: true, json: async () => ({ accessToken, profile }) }
    }
    if (url === '/api/connection') {
      return {
        ok: connectionDeleteSucceeds,
        status: connectionDeleteSucceeds ? 200 : 503,
        json: async () => ({ ok: connectionDeleteSucceeds }),
      }
    }
    if (url === '/api/token') {
      return hasSession
        ? { ok: true, json: async () => ({ accessToken, profile }) }
        : { ok: false, status: 401, json: async () => ({}) }
    }
    return { ok: false, json: async () => ({}) }
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

/**
 * A single mocked backend shared by two independent hook instances — the
 * shape of one real browser profile's cookie jar, observed from multiple
 * tabs. Session state lives in one place so a real `DELETE /api/connection`
 * or successful `/api/auth/callback` call from either tab changes what the
 * *other* tab would see on its own next request, without any direct channel
 * between them.
 */
function stubSharedBackend({
  profile,
  initiallyConnected,
}: {
  profile: GoogleAccountProfile
  initiallyConnected: boolean
}) {
  let hasSession = initiallyConnected
  const fetchMock = vi.fn(async (url: string) => {
    if (url === '/api/auth/callback') {
      hasSession = true
      return { ok: true, json: async () => ({ accessToken: 'access-token', profile }) }
    }
    if (url === '/api/connection') {
      hasSession = false
      return { ok: true, json: async () => ({ ok: true }) }
    }
    if (url === '/api/token') {
      return hasSession
        ? { ok: true, json: async () => ({ accessToken: 'access-token', profile }) }
        : { ok: false, status: 401, json: async () => ({}) }
    }
    return { ok: false, json: async () => ({}) }
  })
  vi.stubGlobal('fetch', fetchMock)
  return { fetchMock, hasSession: () => hasSession }
}

/**
 * Stubs `fetch` for exactly one hook mount's worth of restore, standing in
 * for one independent browser profile with its own backend/cookie jar. Used
 * to prove that two separately mocked profiles never interact.
 */
function stubProfileFetch({
  profile,
  hasSession,
}: {
  profile: GoogleAccountProfile
  hasSession: boolean
}) {
  const fetchMock = vi.fn(async (url: string) => {
    if (url === '/api/connection') {
      return { ok: true, json: async () => ({ ok: true }) }
    }
    if (url === '/api/token') {
      return hasSession
        ? { ok: true, json: async () => ({ accessToken: 'access-token', profile }) }
        : { ok: false, status: 401, json: async () => ({}) }
    }
    return { ok: false, json: async () => ({}) }
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}
