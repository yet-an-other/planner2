import { describe, it, expect, vi } from 'vitest'
import {
  exchangeAuthCode,
  decodeIdToken,
  type GoogleTokensResponse,
  type TokenExchangeConfig,
} from '../token-exchange'

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
