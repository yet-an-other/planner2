export type RuntimeConfig = {
  googleClientId: string
  productVersion: string
}

declare global {
  // Installed synchronously by /runtime-config.js before the SPA module loads.
  var __PLANNER_RUNTIME_CONFIG__: RuntimeConfig | undefined
}

/** Returns the public startup configuration installed by the Planner server. */
export function getRuntimeConfig(): RuntimeConfig {
  const config = globalThis.__PLANNER_RUNTIME_CONFIG__
  if (config === undefined) {
    throw new Error('Planner runtime configuration was not loaded')
  }
  if (
    typeof config !== 'object' ||
    typeof config.googleClientId !== 'string' ||
    typeof config.productVersion !== 'string' ||
    config.productVersion.length === 0
  ) {
    throw new Error('Planner runtime configuration is invalid')
  }
  return config
}
