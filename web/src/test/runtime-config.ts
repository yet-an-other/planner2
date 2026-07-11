import type { RuntimeConfig } from '@/lib/runtime-config'

export function setRuntimeConfig(
  overrides: Partial<RuntimeConfig> = {},
): void {
  globalThis.__PLANNER_RUNTIME_CONFIG__ = {
    googleClientId: 'test-client-id',
    productVersion: 'sha-test000',
    ...overrides,
  }
}
