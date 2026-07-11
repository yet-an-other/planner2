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

function makeApp() {
  return createApp(config, {
    postToGoogle: vi.fn(),
    postToRevoke: vi.fn(),
  })
}

describe('HTTP response policy', () => {
  it('adds baseline browser security headers without adding a CSP', async () => {
    const response = await makeApp().request('/runtime-config.js')

    expect(response.headers.get('strict-transport-security')).toBe(
      'max-age=31536000; includeSubDomains',
    )
    expect(response.headers.get('x-content-type-options')).toBe('nosniff')
    expect(response.headers.get('referrer-policy')).toBe(
      'strict-origin-when-cross-origin',
    )
    expect(response.headers.get('x-frame-options')).toBe('DENY')
    expect(response.headers.has('content-security-policy')).toBe(false)
  })

  it('prevents runtime configuration from being cached', async () => {
    const response = await makeApp().request('/runtime-config.js')

    expect(response.headers.get('cache-control')).toBe('no-store')
  })

  it('revalidates the SPA shell and caches only fingerprinted assets immutably', async () => {
    const app = makeApp()
    app.get('/', (c) => c.html('<main>Planner</main>'))
    app.get('/index.html', (c) => c.html('<main>Planner</main>'))
    app.get('/assets/index-abcdefgh.js', (c) => c.text('asset'))
    app.get('/assets/icons.js', (c) => c.text('not fingerprinted'))

    const [root, index, fingerprinted, plainAsset] = await Promise.all([
      app.request('/'),
      app.request('/index.html'),
      app.request('/assets/index-abcdefgh.js'),
      app.request('/assets/icons.js'),
    ])

    expect(root.headers.get('cache-control')).toBe('no-cache')
    expect(index.headers.get('cache-control')).toBe('no-cache')
    expect(fingerprinted.headers.get('cache-control')).toBe(
      'public, max-age=31536000, immutable',
    )
    expect(plainAsset.headers.has('cache-control')).toBe(false)
  })
})
