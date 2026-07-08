import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto'
import type { Session } from '@planner/shared'

/** Name of the session cookie shared by the API and the SPA. */
export const SESSION_COOKIE_NAME = 'planner.session'

/** ~30 days, in seconds. Re-issued on every refresh so the window slides. */
export const SESSION_MAX_AGE_SECONDS = 60 * 60 * 24 * 30

const IV_LENGTH = 12 // 96-bit nonce, the GCM recommendation
const TAG_LENGTH = 16 // GCM auth tag

/**
 * Encrypts a Session into an opaque, URL-safe cookie value using AES-256-GCM.
 * The output is base64url(iv || authTag || ciphertext); the iv is random per
 * token so the same session serializes differently each time. The key is a
 * 32-byte AES key provided as a 64-char hex string.
 */
export function serializeSession(session: Session, keyHex: string): string {
  const key = parseKey(keyHex)
  const iv = randomBytes(IV_LENGTH)
  const cipher = createCipheriv('aes-256-gcm', key, iv)
  const plaintext = Buffer.from(JSON.stringify(session), 'utf8')
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()])
  const tag = cipher.getAuthTag()
  return Buffer.concat([iv, tag, ciphertext]).toString('base64url')
}

/**
 * Reverses {@link serializeSession}. Any failure — missing value, truncation,
 * tampering (auth-tag mismatch), or wrong key — yields `null`, i.e. "no
 * session", so a bad cookie is always treated as logged out, never as an error.
 */
export function parseSession(
  cookieValue: string | undefined,
  keyHex: string,
): Session | null {
  if (!cookieValue) {
    return null
  }

  try {
    const key = parseKey(keyHex)
    const buf = Buffer.from(cookieValue, 'base64url')
    if (buf.length < IV_LENGTH + TAG_LENGTH) {
      return null
    }
    const iv = buf.subarray(0, IV_LENGTH)
    const tag = buf.subarray(IV_LENGTH, IV_LENGTH + TAG_LENGTH)
    const ciphertext = buf.subarray(IV_LENGTH + TAG_LENGTH)
    const decipher = createDecipheriv('aes-256-gcm', key, iv)
    decipher.setAuthTag(tag)
    const plaintext = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ])
    return JSON.parse(plaintext.toString('utf8')) as Session
  } catch {
    return null
  }
}

function parseKey(keyHex: string): Buffer {
  const key = Buffer.from(keyHex, 'hex')
  if (key.length !== 32) {
    throw new Error('session cookie key must be 32 bytes (64 hex chars)')
  }
  return key
}

/** Builds a persistent, first-party session `Set-Cookie` header. */
export function sessionCookieHeader(value: string): string {
  return cookieHeader(value, SESSION_MAX_AGE_SECONDS)
}

/** Builds a `Set-Cookie` header that clears the session cookie immediately. */
export function clearedSessionCookieHeader(): string {
  return cookieHeader('', 0)
}

function cookieHeader(value: string, maxAge: number): string {
  return `${SESSION_COOKIE_NAME}=${value}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${maxAge}`
}
