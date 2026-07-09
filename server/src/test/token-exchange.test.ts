import { describe, it, expect, vi } from 'vitest'
import {
  exchangeAuthCode,
  decodeIdToken,
  refreshIfNeeded,
  type GoogleTokensResponse,
  type TokenExchangeConfig,
} from '../token-exchange'
import type { Session } from '@planner/shared'

const config: TokenExchangeConfig = {
  clientId: 'cid',
  clientSecret: 'secret',
  redirectUri: 'postmessage',
}

function makeIdToken(claims: Record<string, unknown>): string {
  const header = Buffer.from(JSON.stringify({ alg: 'RS256' })).toString('base64url')
  const payload = Buffer.from(JSON.stringify(claims)).toString('base64url')
  return `${header}.${payload}.signature`
}

describe('exchangeAuthCode', () => {
  it('exchanges a code for a session, decoding the profile from the id_token', async () => {
    const postToGoogle = vi.fn(async (body: URLSearchParams): Promise<GoogleTokensResponse> => {
      expect(body.get('client_id')).toBe('cid')
      expect(body.get('client_secret')).toBe('secret')
      expect(body.get('grant_type')).toBe('authorization_code')
      expect(body.get('redirect_uri')).toBe('postmessage')
      expect(body.get('code')).toBe('the-code')
      return {
        access_token: 'access',
        expires_in: 3600,
        refresh_token: 'refresh',
        id_token: makeIdToken({
          email: 'user@example.com',
          name: 'User Example',
          picture: 'pic-url',
        }),
      }
    })

    const session = await exchangeAuthCode('the-code', config, { postToGoogle })

    expect(session.accessToken).toBe('access')
    expect(session.refreshToken).toBe('refresh')
    expect(session.profile.email).toBe('user@example.com')
    expect(session.profile.displayName).toBe('User Example')
    expect(session.profile.pictureUrl).toBe('pic-url')
    expect(session.profile.initials).toBe('UE')
    // expires_in of 3600s → accessTokenExpiresAt is roughly now + 1h.
    expect(session.accessTokenExpiresAt).toBeGreaterThan(Date.now())
  })
})

describe('decodeIdToken', () => {
  it('falls back to the email when the name claim is absent', () => {
    const profile = decodeIdToken(makeIdToken({ email: 'user@example.com' }))

    expect(profile.displayName).toBe('user@example.com')
    expect(profile.initials).toBe('U')
    expect(profile.pictureUrl).toBeNull()
  })
})

describe('refreshIfNeeded', () => {
  const config: TokenExchangeConfig = {
    clientId: 'cid',
    clientSecret: 'secret',
    redirectUri: 'postmessage',
  }

  const sessionAt = (expiresAt: number): Session => ({
    accessToken: 'old-access',
    accessTokenExpiresAt: expiresAt,
    refreshToken: 'refresh',
    profile: {
      email: 'u@example.com',
      displayName: 'U',
      initials: 'U',
      pictureUrl: null,
    },
  })

  it('returns the session unchanged (and does not call Google) while the token is valid', async () => {
    const postToGoogle = vi.fn()
    // expiry 100000, skew 60000 -> fresh until now < 40000.
    const result = await refreshIfNeeded(sessionAt(100_000), config, { postToGoogle }, 5_000)

    expect(result.refreshed).toBe(false)
    expect(result.session).toEqual(sessionAt(100_000))
    expect(postToGoogle).not.toHaveBeenCalled()
  })

  it('refreshes via the refresh-token grant when the token is stale', async () => {
    const postToGoogle = vi.fn(async (body: URLSearchParams): Promise<GoogleTokensResponse> => {
      expect(body.get('grant_type')).toBe('refresh_token')
      expect(body.get('refresh_token')).toBe('refresh')
      expect(body.get('client_id')).toBe('cid')
      expect(body.get('client_secret')).toBe('secret')
      return { access_token: 'new-access', expires_in: 3600, id_token: 'ignored' }
    })
    // expiry 100000, now 50000 -> 50000 >= 40000 -> stale.
    const result = await refreshIfNeeded(sessionAt(100_000), config, { postToGoogle }, 50_000)

    expect(result.refreshed).toBe(true)
    expect(result.session.accessToken).toBe('new-access')
    expect(result.session.refreshToken).toBe('refresh')
    expect(result.session.profile.email).toBe('u@example.com')
    expect(result.session.accessTokenExpiresAt).toBeGreaterThan(50_000)
  })

  it('refreshes at the skew boundary (now == expiry - skew) but not one tick before', async () => {
    const postToGoogle = vi.fn(async (): Promise<GoogleTokensResponse> => ({
      access_token: 'new-access',
      expires_in: 3600,
      id_token: 'ignored',
    }))
    // expiry 100000, skew 60000 -> boundary at now = 40000.
    const fresh = await refreshIfNeeded(sessionAt(100_000), config, { postToGoogle }, 39_999)
    const stale = await refreshIfNeeded(sessionAt(100_000), config, { postToGoogle }, 40_000)

    expect(fresh.refreshed).toBe(false)
    expect(stale.refreshed).toBe(true)
  })
})
