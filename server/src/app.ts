import { Hono } from 'hono'
import { getCookie } from 'hono/cookie'
import type { AuthCallbackRequest } from '@planner/shared'
import {
  serializeSession,
  parseSession,
  sessionCookieHeader,
  clearedSessionCookieHeader,
  SESSION_COOKIE_NAME,
} from './session-cookie'
import {
  exchangeAuthCode,
  refreshIfNeeded,
  revokeRefreshToken,
  type RevokeDeps,
  type TokenExchangeConfig,
  type TokenExchangeDeps,
} from './token-exchange'

/** Server-side OAuth credentials plus the cookie-encryption key. */
export type AppConfig = TokenExchangeConfig & { cookieKey: string }

/** Injectable Google HTTP collaborators: token endpoint + revocation endpoint. */
export type AppDeps = TokenExchangeDeps & RevokeDeps

/**
 * Builds the API Hono app. Config and the Google HTTP dependency are injected
 * so the endpoints are unit-testable without a network. The SPA static-serving
 * fallback is wired separately at runtime (see `index.ts`).
 */
export function createApp(config: AppConfig, deps: AppDeps): Hono {
  const app = new Hono()

  app.post('/api/auth/callback', async (c) => {
    const { code } = await c.req.json<AuthCallbackRequest>()
    const session = await exchangeAuthCode(code, config, deps)
    c.header('Set-Cookie', sessionCookieHeader(serializeSession(session, config.cookieKey)))
    return c.json({ accessToken: session.accessToken, profile: session.profile })
  })

  app.get('/api/token', async (c) => {
    const session = parseSession(getCookie(c, SESSION_COOKIE_NAME), config.cookieKey)
    if (!session) {
      return c.json({ error: 'no session' }, 401)
    }
    const result = await refreshIfNeeded(session, config, deps)
    // Re-issue the cookie on every call so the 30-day window slides with use
    // (a fresh IV makes the value differ even when the session did not change).
    c.header(
      'Set-Cookie',
      sessionCookieHeader(serializeSession(result.session, config.cookieKey)),
    )
    return c.json({
      accessToken: result.session.accessToken,
      profile: result.session.profile,
    })
  })

  app.post('/api/logout', async (c) => {
    const session = parseSession(getCookie(c, SESSION_COOKIE_NAME), config.cookieKey)
    if (session) {
      try {
        await revokeRefreshToken(session, deps)
      } catch {
        // Best-effort: clear the local session even if Google revocation failed
        // (e.g. a transient network error) so the user is still logged out here.
      }
    }
    c.header('Set-Cookie', clearedSessionCookieHeader())
    return c.json({ ok: true })
  })

  return app
}
