import { serve } from '@hono/node-server'
import { serveStatic } from '@hono/node-server/serve-static'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp } from './app'
import type { GoogleTokensResponse } from './token-exchange'

const clientId = requireEnv('GOOGLE_CLIENT_ID')
const clientSecret = requireEnv('GOOGLE_CLIENT_SECRET')
const cookieKey = requireCookieKey()
const port = Number(process.env.PORT ?? 3000)

// The built SPA, served from the same origin so the session cookie is first-party.
const here = path.dirname(fileURLToPath(import.meta.url))
const absoluteStaticRoot = path.resolve(
  process.env.SPA_DIST ?? path.resolve(here, '../../web/dist'),
)
// serveStatic only accepts a root relative to the current working directory.
const staticRoot = path.relative(process.cwd(), absoluteStaticRoot)

const app = createApp(
  { clientId, clientSecret, redirectUri: 'postmessage', cookieKey },
  {
    postToGoogle: async (body) => {
      const response = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      })
      if (!response.ok) {
        throw new Error('Google token exchange failed')
      }
      return (await response.json()) as GoogleTokensResponse
    },
    postToRevoke: async (body) => {
      const response = await fetch('https://oauth2.googleapis.com/revoke', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      })
      if (!response.ok) {
        throw new Error('Google token revocation failed')
      }
    },
  },
)

// Serve the SPA shell and assets. Registered after the /api routes, so
// /api/auth/callback and /api/token win on specificity; everything else falls
// through to the static file server (with index.html for '/').
app.get('/*', serveStatic({ root: staticRoot, index: 'index.html' }))

serve({ fetch: app.fetch, port }, (info) => {
  console.log(`planner server listening on http://localhost:${info.port}`)
})

function requireEnv(name: string): string {
  const value = process.env[name]
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`)
  }
  return value
}

function requireCookieKey(): string {
  const value = requireEnv('SESSION_COOKIE_KEY')
  if (Buffer.from(value, 'hex').length !== 32) {
    throw new Error('SESSION_COOKIE_KEY must be 32 bytes (64 hex chars)')
  }
  return value
}
