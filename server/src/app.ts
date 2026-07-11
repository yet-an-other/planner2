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
import type { OperationalState } from './operations'
import { accessLog } from './access-log'
import { httpPolicy } from './http-policy'
import {
  exchangeAuthCode,
  refreshIfNeeded,
  revokeRefreshToken,
  type RevokeDeps,
  type TokenExchangeConfig,
  type TokenExchangeDeps,
} from './token-exchange'

/** Server-side OAuth credentials plus startup-computed public configuration. */
export type AppConfig = TokenExchangeConfig & {
  cookieKey: string
  runtimeConfigScript: string
  productVersion: string
  operations: OperationalState
}

/** Injectable Google HTTP collaborators plus operational logging seams. */
export type AppDeps = TokenExchangeDeps &
  RevokeDeps & {
    writeAccessLog?: (line: string) => void
    now?: () => number
  }

/**
 * Builds the API Hono app. Config and the Google HTTP dependency are injected
 * so the endpoints are unit-testable without a network. The SPA static-serving
 * fallback is wired separately at runtime (see `index.ts`).
 */
export function createApp(config: AppConfig, deps: AppDeps): Hono {
  const app = new Hono()

  app.use('*', httpPolicy())
  if (deps.writeAccessLog !== undefined) {
    app.use(
      '*',
      accessLog({
        productVersion: config.productVersion,
        write: deps.writeAccessLog,
        now: deps.now,
      }),
    )
  }

  app.get('/healthz', (c) => {
    const operationalStatus = config.operations.status()
    return c.json(
      {
        status: operationalStatus === 'ready' ? 'ok' : operationalStatus,
        productVersion: config.productVersion,
      },
      operationalStatus === 'ready' ? 200 : 503,
    )
  })

  app.get('/runtime-config.js', (c) =>
    c.body(config.runtimeConfigScript, 200, {
      'Content-Type': 'text/javascript; charset=UTF-8',
    }),
  )

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
    if (result.status === 'revoked') {
      // The grant was revoked at Google: drop the session gracefully so the SPA
      // falls back to the disconnected state (Saved Busy Blocks), not an error.
      c.header('Set-Cookie', clearedSessionCookieHeader())
      return c.json({ error: 'session revoked' }, 401)
    }
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
