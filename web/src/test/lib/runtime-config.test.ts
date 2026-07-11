import { afterEach, describe, expect, it } from 'vitest'
import { getRuntimeConfig } from '@/lib/runtime-config'

afterEach(() => {
  delete globalThis.__PLANNER_RUNTIME_CONFIG__
})

describe('getRuntimeConfig', () => {
  it('returns the Google client id and Product Version installed before the SPA starts', () => {
    globalThis.__PLANNER_RUNTIME_CONFIG__ = {
      googleClientId: 'runtime-client-id',
      productVersion: 'sha-abcdef0',
    }

    expect(getRuntimeConfig()).toEqual({
      googleClientId: 'runtime-client-id',
      productVersion: 'sha-abcdef0',
    })
  })

  it('fails clearly when the runtime configuration script was not loaded', () => {
    delete globalThis.__PLANNER_RUNTIME_CONFIG__

    expect(() => getRuntimeConfig()).toThrow(
      'Planner runtime configuration was not loaded',
    )
  })

  it('fails clearly when runtime configuration is malformed', () => {
    globalThis.__PLANNER_RUNTIME_CONFIG__ = {
      googleClientId: 'runtime-client-id',
      productVersion: '',
    }

    expect(() => getRuntimeConfig()).toThrow(
      'Planner runtime configuration is invalid',
    )
  })
})
