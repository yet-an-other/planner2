import { describe, it, expect, vi } from 'vitest'
import { createApp, type AppConfig } from '../app'
import { serializeSession, SESSION_COOKIE_NAME } from '../session-cookie'
import type { GoogleTokensResponse } from '../token-exchange'
import type { Session } from '@planner/shared'

const KEY = '00'.repeat(32)
const config: AppConfig = {
  clientId: 'cid',
  clientSecret: 'secret',
  redirectUri: 'postmessage',
  cookieKey: KEY,
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

describe('POST /api/auth/callback', () => {
  it('exchanges the code, sets the session cookie, and returns the profile', async () => {
    const postToGoogle = vi.fn(async (): Promise<GoogleTokensResponse> => ({
      access_token: 'access',
      expires_in: 3600,
      refresh_token: 'refresh',
      id_token: makeIdToken({ email: 'user@example.com', name: 'User Example' }),
    }))
    const app = createApp(config, { postToGoogle })

    const res = await app.request('/api/auth/callback', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ code: 'the-code' }),
    })

    expect(res.status).toBe(200)
    const body = (await res.json()) as { profile: { email: string } }
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
  it('returns the cached access token from a valid session cookie', async () => {
    const postToGoogle = vi.fn()
    const cookie = `${SESSION_COOKIE_NAME}=${serializeSession(session, KEY)}`
    const app = createApp(config, { postToGoogle })

    const res = await app.request('/api/token', { headers: { Cookie: cookie } })

    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ accessToken: 'access' })
    // Serving a cached token must not hit Google.
    expect(postToGoogle).not.toHaveBeenCalled()
  })

  it('returns 401 when there is no session cookie', async () => {
    const app = createApp(config, { postToGoogle: vi.fn() })

    const res = await app.request('/api/token')

    expect(res.status).toBe(401)
  })
})
