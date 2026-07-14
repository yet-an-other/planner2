import { describe, expect, it } from 'vitest'
import {
  loadRuntimeConfig,
  serializePublicRuntimeConfig,
} from '../runtime-config'

const validEnvironment = {
  VITE_GOOGLE_CLIENT_ID: 'planner.apps.googleusercontent.com',
  GOOGLE_CLIENT_ID: 'planner.apps.googleusercontent.com',
  GOOGLE_CLIENT_SECRET: 'private-client-secret',
  SESSION_COOKIE_KEY: 'ab'.repeat(32),
  APP_VERSION: 'sha-abcdef0',
}

describe('loadRuntimeConfig', () => {
  it.each(['VITE_GOOGLE_CLIENT_ID', 'GOOGLE_CLIENT_ID'] as const)(
    'rejects a missing %s',
    (name) => {
      expect(() => loadRuntimeConfig({ ...validEnvironment, [name]: '' })).toThrow(
        `Missing required environment variable: ${name}`,
      )
    },
  )

  it('requires a deployed Product Version', () => {
    expect(() =>
      loadRuntimeConfig({ ...validEnvironment, APP_VERSION: undefined }),
    ).toThrow('Missing required environment variable: APP_VERSION')
  })

  it('rejects client ids that do not identify the same OAuth client', () => {
    expect(() =>
      loadRuntimeConfig({
        ...validEnvironment,
        VITE_GOOGLE_CLIENT_ID: 'browser.apps.googleusercontent.com',
      }),
    ).toThrow('VITE_GOOGLE_CLIENT_ID must match GOOGLE_CLIENT_ID')
  })

  it('separates private server credentials from public browser configuration', () => {
    const config = loadRuntimeConfig(validEnvironment)

    expect(config.server).toEqual({
      clientId: 'planner.apps.googleusercontent.com',
      clientSecret: 'private-client-secret',
      redirectUri: 'postmessage',
      cookieKey: 'ab'.repeat(32),
    })
    expect(config.public).toEqual({
      googleClientId: 'planner.apps.googleusercontent.com',
      productVersion: 'sha-abcdef0',
    })
  })

  it('rejects a cookie key that is not exactly 64 hexadecimal characters', () => {
    expect(() =>
      loadRuntimeConfig({ ...validEnvironment, SESSION_COOKIE_KEY: 'z'.repeat(64) }),
    ).toThrow('SESSION_COOKIE_KEY must be 32 bytes (64 hex chars)')
  })
})

describe('serializePublicRuntimeConfig', () => {
  it('produces an executable assignment without exposing private configuration', () => {
    const config = loadRuntimeConfig(validEnvironment)
    const script = serializePublicRuntimeConfig(config.public)

    expect(script).toContain('globalThis.__PLANNER_RUNTIME_CONFIG__=')
    expect(script).toContain('planner.apps.googleusercontent.com')
    expect(script).toContain('sha-abcdef0')
    expect(script).not.toContain('private-client-secret')
    expect(script).not.toContain('abababab')
  })

  it('escapes characters that can terminate or corrupt an inline script', () => {
    const script = serializePublicRuntimeConfig({
      googleClientId: '</script><script>alert(1)</script>&',
      productVersion: 'sha-line\u2028next\u2029last',
    })

    expect(script).not.toContain('<')
    expect(script).not.toContain('>')
    expect(script).not.toContain('&')
    expect(script).not.toContain('\u2028')
    expect(script).not.toContain('\u2029')
    expect(script).toContain('\\u003c')
    expect(script).toContain('\\u2028')
    expect(script).toContain('\\u2029')
  })
})
