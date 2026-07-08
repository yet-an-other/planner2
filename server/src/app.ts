import { Hono } from 'hono'
import { getCookie } from 'hono/cookie'
import type { AuthCallbackRequest } from '@planner/shared'
import {
  serializeSession,
  parseSession,
  sessionCookieHeader,
  SESSION_COOKIE_NAME,
} from './session-cookie'
import {
  exchangeAuthCode,
  type TokenExchangeConfig,
  type TokenExchangeDeps,
} from './token-exchange'

/** Server-side OAuth credentials plus the cookie-encryption key. */
export type AppConfig = TokenExchangeConfig & { cookieKey: string }

/**
 * Builds the API Hono app. Config and the Google HTTP dependency are injected
 * so the endpoints are unit-testable without a network. The SPA static-serving
 * fallback is wired separately at runtime (see `index.ts`).
 */
export function createApp(config: AppConfig, deps: TokenExchangeDeps): Hono {
  const app = new Hono()

  app.post('/api/auth/callback', async (c) => {
    const { code } = await c.req.json<AuthCallbackRequest>()
    const session = await exchangeAuthCode(code, config, deps)
    c.header('Set-Cookie', sessionCookieHeader(serializeSession(session, config.cookieKey)))
    return c.json({ profile: session.profile })
  })

  app.get('/api/token', (c) => {
    const session = parseSession(getCookie(c, SESSION_COOKIE_NAME), config.cookieKey)
    if (!session) {
      return c.json({ error: 'no session' }, 401)
    }
    // No refresh yet (ADR 0005 slice 1): the token was just exchanged.
    return c.json({ accessToken: session.accessToken })
  })

  return app
}
