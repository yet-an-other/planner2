import type { MiddlewareHandler } from 'hono'

const IMMUTABLE_ASSET = /^\/assets\/.+-[A-Za-z0-9_-]{8,}\.[A-Za-z0-9]+$/

/** Applies the browser security and cache contract to every served response. */
export function httpPolicy(): MiddlewareHandler {
  return async (c, next) => {
    c.header(
      'Strict-Transport-Security',
      'max-age=31536000; includeSubDomains',
    )
    c.header('X-Content-Type-Options', 'nosniff')
    c.header('Referrer-Policy', 'strict-origin-when-cross-origin')
    c.header('X-Frame-Options', 'DENY')

    const cacheControl = cacheControlForPath(c.req.path)
    if (cacheControl !== undefined) {
      c.header('Cache-Control', cacheControl)
    }

    await next()
  }
}

export function cacheControlForPath(pathname: string): string | undefined {
  if (pathname === '/runtime-config.js') return 'no-store'
  if (pathname === '/' || pathname === '/index.html') return 'no-cache'
  if (IMMUTABLE_ASSET.test(pathname)) {
    return 'public, max-age=31536000, immutable'
  }
  return undefined
}
