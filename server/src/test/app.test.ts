import { describe, it, expect, vi } from 'vitest'
import { createApp, type AppConfig } from '../app'
import { serializeSession, SESSION_COOKIE_NAME } from '../session-cookie'
import { GoogleTokenError, type GoogleTokensResponse } from '../token-exchange'
import type { Session } from '@planner/shared'
import { createOperationalState } from '../operations'

const KEY = '00'.repeat(32)
const readyOperations = createOperationalState()
readyOperations.markReady()
const config: AppConfig = {
  clientId: 'cid',
  clientSecret: 'secret',
  redirectUri: 'postmessage',
  cookieKey: KEY,
  runtimeConfigScript:
    'globalThis.__PLANNER_RUNTIME_CONFIG__={"googleClientId":"cid","productVersion":"sha-abcdef0"};',
  productVersion: 'sha-abcdef0',
  operations: readyOperations,
}

function makeIdToken(claims: Record<string, unknown>): string {
  const payload = Buffer.from(JSON.stringify(claims)).toString('base64url')
  return `header.${payload}.signature`
}

const session: Session = {
  accessToken: 'access',
  accessTokenExpiresAt: Date.now() + 3_600_000,
  refreshToken: 'refresh',
  profile: {
    email: 'u@example.com',
    displayName: 'U E',
    initials: 'UE',
    pictureUrl: null,
  },
}

describe('GET /healthz', () => {
  it('does not report ready before server startup completes', async () => {
    const operations = createOperationalState()
    const app = createApp(
      { ...config, operations },
      { postToGoogle: vi.fn(), postToRevoke: vi.fn() },
    )

    const response = await app.request('/healthz')

    expect(response.status).toBe(503)
    expect(await response.json()).toEqual({
      status: 'starting',
      productVersion: 'sha-abcdef0',
    })
  })

  it('reports process health and Product Version without calling Google', async () => {
    const postToGoogle = vi.fn()
    const app = createApp(config, { postToGoogle, postToRevoke: vi.fn() })

    const response = await app.request('/healthz')

    expect(response.status).toBe(200)
    expect(await response.json()).toEqual({
      status: 'ok',
      productVersion: 'sha-abcdef0',
    })
    expect(postToGoogle).not.toHaveBeenCalled()
  })

  it('stops reporting ready when shutdown begins', async () => {
    const operations = createOperationalState()
    const app = createApp(
      { ...config, operations },
      { postToGoogle: vi.fn(), postToRevoke: vi.fn() },
    )
    operations.markReady()
    operations.beginShutdown()

    const response = await app.request('/healthz')

    expect(response.status).toBe(503)
    expect(await response.json()).toEqual({
      status: 'shutting-down',
      productVersion: 'sha-abcdef0',
    })
  })
})

describe('GET /runtime-config.js', () => {
  it('serves the precomputed public runtime configuration from memory', async () => {
    const app = createApp(config, { postToGoogle: vi.fn(), postToRevoke: vi.fn() })

    const response = await app.request('/runtime-config.js')

    expect(response.status).toBe(200)
    expect(response.headers.get('content-type')).toContain('text/javascript')
    expect(await response.text()).toBe(config.runtimeConfigScript)
  })
})

describe('POST /api/auth/callback', () => {
  it('exchanges the code, sets the session cookie, and returns the profile', async () => {
    const postToGoogle = vi.fn(async (): Promise<GoogleTokensResponse> => ({
      access_token: 'access',
      expires_in: 3600,
      refresh_token: 'refresh',
      id_token: makeIdToken({ email: 'user@example.com', name: 'User Example' }),
    }))
    const app = createApp(config, { postToGoogle, postToRevoke: vi.fn() })

    const res = await app.request('/api/auth/callback', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: 'the-code' }),
    })

    expect(res.status).toBe(200)
    const body = (await res.json()) as {
      accessToken: string
      profile: { email: string }
    }
    expect(body.accessToken).toBe('access')
    expect(body.profile.email).toBe('user@example.com')

    const setCookie = res.headers.get('set-cookie') ?? ''
    expect(setCookie).toContain(`${SESSION_COOKIE_NAME}=`)
    expect(setCookie).toContain('HttpOnly')
    expect(setCookie).toContain('Secure')
    expect(setCookie).toContain('SameSite=Lax')
    expect(setCookie).toContain('Max-Age=2592000')
    // The refresh token must never appear in plaintext in the header.
    expect(setCookie).not.toContain('refresh')
  })
})

describe('GET /api/token', () => {
  it('returns the cached access token and profile (no Google call) and rolls the cookie', async () => {
    const postToGoogle = vi.fn()
    const freshSession = { ...session, accessTokenExpiresAt: Date.now() + 3_600_000 }
    const cookie = `${SESSION_COOKIE_NAME}=${serializeSession(freshSession, KEY)}`
    const app = createApp(config, { postToGoogle, postToRevoke: vi.fn() })

    const res = await app.request('/api/token', { headers: { Cookie: cookie } })

    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({
      accessToken: 'access',
      profile: session.profile,
    })
    // Serving a cached token must not hit Google.
    expect(postToGoogle).not.toHaveBeenCalled()
    // The cookie is re-issued (sliding window) even without a refresh.
    expect(res.headers.get('set-cookie')).toContain('Max-Age=2592000')
  })

  it('refreshes a stale token via Google and re-sets the cookie', async () => {
    const postToGoogle = vi.fn(async (): Promise<GoogleTokensResponse> => ({
      access_token: 'new-access',
      expires_in: 3600,
      id_token: 'ignored',
    }))
    const staleSession = { ...session, accessTokenExpiresAt: 0 }
    const cookie = `${SESSION_COOKIE_NAME}=${serializeSession(staleSession, KEY)}`
    const app = createApp(config, { postToGoogle, postToRevoke: vi.fn() })

    const res = await app.request('/api/token', { headers: { Cookie: cookie } })

    expect(res.status).toBe(200)
    const body = (await res.json()) as { accessToken: string }
    expect(body.accessToken).toBe('new-access')
    expect(postToGoogle).toHaveBeenCalledWith(expect.any(URLSearchParams))
    expect(res.headers.get('set-cookie')).toContain('Max-Age=2592000')
  })

  it('returns 401 and clears the cookie when the grant has been revoked', async () => {
    const postToGoogle = vi.fn(async (): Promise<GoogleTokensResponse> => {
      throw new GoogleTokenError('invalid_grant')
    })
    const staleSession = { ...session, accessTokenExpiresAt: 0 }
    const cookie = `${SESSION_COOKIE_NAME}=${serializeSession(staleSession, KEY)}`
    const app = createApp(config, { postToGoogle, postToRevoke: vi.fn() })

    const res = await app.request('/api/token', { headers: { Cookie: cookie } })

    expect(res.status).toBe(401)
    expect(res.headers.get('set-cookie')).toContain('Max-Age=0')
  })

  it('returns 401 when there is no session cookie', async () => {
    const app = createApp(config, { postToGoogle: vi.fn(), postToRevoke: vi.fn() })

    const res = await app.request('/api/token')

    expect(res.status).toBe(401)
  })
})

describe('POST /api/logout', () => {
  it('revokes the refresh token at Google and clears the session cookie', async () => {
    const postToRevoke = vi.fn(async (_body: URLSearchParams) => {})
    const cookie = `${SESSION_COOKIE_NAME}=${serializeSession(session, KEY)}`
    const app = createApp(config, { postToGoogle: vi.fn(), postToRevoke })

    const res = await app.request('/api/logout', {
      method: 'POST',
      headers: { Cookie: cookie },
    })

    expect(res.status).toBe(200)
    expect(postToRevoke).toHaveBeenCalledWith(expect.any(URLSearchParams))
    const body = postToRevoke.mock.calls[0]![0] as URLSearchParams
    expect(body.get('token')).toBe('refresh')
    expect(body.get('token_type_hint')).toBe('refresh_token')
    const setCookie = res.headers.get('set-cookie') ?? ''
    expect(setCookie).toContain(`${SESSION_COOKIE_NAME}=`)
    expect(setCookie).toContain('Max-Age=0')
  })

  it('clears the cookie even when there is no session (idempotent)', async () => {
    const postToRevoke = vi.fn()
    const app = createApp(config, { postToGoogle: vi.fn(), postToRevoke })

    const res = await app.request('/api/logout', { method: 'POST' })

    expect(res.status).toBe(200)
    expect(postToRevoke).not.toHaveBeenCalled()
    expect(res.headers.get('set-cookie')).toContain('Max-Age=0')
  })
})
