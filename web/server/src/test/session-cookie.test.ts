import { describe, it, expect } from 'vitest'
import {
  serializeSession,
  parseSession,
  sessionCookieHeader,
  clearedSessionCookieHeader,
  SESSION_COOKIE_NAME,
} from '../session-cookie'
import type { Session } from '../session'

const KEY = '00'.repeat(32) // 32-byte AES-256 key as hex

const session: Session = {
  accessToken: 'access-token',
  accessTokenExpiresAt: 1_700_000_000_000,
  refreshToken: 'refresh-token',
  profile: {
    email: 'user@example.com',
    displayName: 'User Example',
    initials: 'UE',
    pictureUrl: null,
  },
}

describe('session cookie', () => {
  it('round-trips a session through encrypt then decrypt', () => {
    const encrypted = serializeSession(session, KEY)

    // The cookie value must not leak the session as plaintext.
    expect(encrypted).not.toContain(session.accessToken)
    expect(encrypted).not.toContain(session.refreshToken)
    expect(encrypted).not.toContain(session.profile.email)

    expect(parseSession(encrypted, KEY)).toEqual(session)
  })

  it('returns null for a tampered cookie value', () => {
    const encrypted = serializeSession(session, KEY)
    const chars = [...encrypted]
    const i = Math.floor(chars.length / 2)
    chars[i] = chars[i] === 'A' ? 'B' : 'A'

    expect(parseSession(chars.join(''), KEY)).toBeNull()
  })

  it('returns null for a non-cookie garbage string', () => {
    expect(parseSession('not-a-valid-cookie', KEY)).toBeNull()
  })

  it('returns null when decrypted with the wrong key', () => {
    const encrypted = serializeSession(session, KEY)

    expect(parseSession(encrypted, '01'.repeat(32))).toBeNull()
  })

  it('returns null for an empty or missing value', () => {
    expect(parseSession(undefined, KEY)).toBeNull()
    expect(parseSession('', KEY)).toBeNull()
  })

  it('builds a Set-Cookie header with secure, same-site, persistent attributes', () => {
    const value = serializeSession(session, KEY)
    const header = sessionCookieHeader(value)

    expect(header).toBe(
      `${SESSION_COOKIE_NAME}=${value}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=2592000`,
    )
  })

  it('builds a cleared Set-Cookie header that expires immediately', () => {
    const header = clearedSessionCookieHeader()

    expect(header).toBe(
      `${SESSION_COOKIE_NAME}=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0`,
    )
  })
})
