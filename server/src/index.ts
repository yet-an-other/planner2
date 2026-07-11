import { serve } from '@hono/node-server'
import { serveStatic } from '@hono/node-server/serve-static'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp } from './app'
import {
  loadRuntimeConfig,
  serializePublicRuntimeConfig,
} from './runtime-config'
import { createGracefulShutdown, createOperationalState } from './operations'
import { GoogleTokenError, type GoogleTokensResponse } from './token-exchange'

const runtimeConfig = loadRuntimeConfig(process.env)
const operations = createOperationalState()
const port = Number(process.env.PORT ?? 3000)

// The built SPA, served from the same origin so the session cookie is first-party.
const here = path.dirname(fileURLToPath(import.meta.url))
const absoluteStaticRoot = path.resolve(
  process.env.SPA_DIST ?? path.resolve(here, '../../web/dist'),
)
// serveStatic only accepts a root relative to the current working directory.
const staticRoot = path.relative(process.cwd(), absoluteStaticRoot)

const app = createApp(
  {
    ...runtimeConfig.server,
    runtimeConfigScript: serializePublicRuntimeConfig(runtimeConfig.public),
    productVersion: runtimeConfig.public.productVersion,
    operations,
  },
  {
    writeAccessLog: (line) => console.log(line),
    postToGoogle: async (body) => {
      const response = await fetch('https://oauth2.googleapis.com/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString(),
      })
      if (!response.ok) {
        const errorBody = (await response.json().catch(() => ({}))) as {
          error?: string
          error_description?: string
        }
        throw new GoogleTokenError(
          errorBody.error ?? 'unknown',
          errorBody.error_description,
        )
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

const server = serve({ fetch: app.fetch, port }, (info) => {
  operations.markReady()
  console.log(`planner server listening on http://localhost:${info.port}`)
})

const shutdown = createGracefulShutdown({ operations, server })
for (const signal of ['SIGTERM', 'SIGINT'] as const) {
  process.once(signal, () => {
    void shutdown().catch((error: unknown) => {
      console.error('planner server shutdown failed', error)
      process.exitCode = 1
    })
  })
}
