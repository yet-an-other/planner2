import { describe, expect, it, vi } from 'vitest'
import { createApp, type AppConfig } from '../app'
import { createOperationalState } from '../operations'

const config: AppConfig = {
  clientId: 'cid',
  clientSecret: 'secret',
  redirectUri: 'postmessage',
  cookieKey: '00'.repeat(32),
  runtimeConfigScript: 'globalThis.__PLANNER_RUNTIME_CONFIG__={};',
  productVersion: 'sha-abcdef0',
  operations: createOperationalState(),
}

describe('privacy-safe access logging', () => {
  it('writes method, pathname, status, duration, and Product Version as JSON', async () => {
    const write = vi.fn<(line: string) => void>()
    const now = vi.fn().mockReturnValueOnce(100).mockReturnValueOnce(112)
    const app = createApp(config, {
      postToGoogle: vi.fn(),
      writeAccessLog: write,
      now,
    })

    await app.request('/api/token?authorization=query-secret')

    expect(write).toHaveBeenCalledOnce()
    expect(JSON.parse(write.mock.calls[0][0])).toEqual({
      method: 'GET',
      path: '/api/token',
      status: 401,
      durationMs: 12,
      productVersion: 'sha-abcdef0',
    })
  })

  it('never records query values, headers, cookies, or request bodies', async () => {
    const write = vi.fn<(line: string) => void>()
    const app = createApp(config, {
      postToGoogle: vi.fn(),
      writeAccessLog: write,
    })

    await app.request('/api/connection?token=query-secret', {
      method: 'DELETE',
      headers: {
        Authorization: 'Bearer header-secret',
        Cookie: 'planner_session=cookie-secret',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ token: 'body-secret' }),
    })

    const line = write.mock.calls[0][0]
    expect(line).not.toContain('query-secret')
    expect(line).not.toContain('header-secret')
    expect(line).not.toContain('cookie-secret')
    expect(line).not.toContain('body-secret')
    expect(JSON.parse(line).path).toBe('/api/connection')
  })

  it('omits health-probe requests', async () => {
    const write = vi.fn<(line: string) => void>()
    const app = createApp(config, {
      postToGoogle: vi.fn(),
      writeAccessLog: write,
    })

    await app.request('/healthz?probe=secret')

    expect(write).not.toHaveBeenCalled()
  })
})
