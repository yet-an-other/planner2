import type { MiddlewareHandler } from 'hono'

export type AccessLogOptions = {
  productVersion: string
  write: (line: string) => void
  now?: () => number
}

type AccessRecord = {
  method: string
  path: string
  status: number
  durationMs: number
  productVersion: string
}

/** Emits only an allowlisted, query-free request record after the response. */
export function accessLog({
  productVersion,
  write,
  now = Date.now,
}: AccessLogOptions): MiddlewareHandler {
  return async (c, next) => {
    if (c.req.path === '/healthz') {
      await next()
      return
    }

    const startedAt = now()
    await next()

    const record: AccessRecord = {
      method: c.req.method,
      path: c.req.path,
      status: c.res.status,
      durationMs: Math.max(0, now() - startedAt),
      productVersion,
    }
    write(JSON.stringify(record))
  }
}
