import type { TokenExchangeConfig } from './token-exchange'

export type PublicRuntimeConfig = {
  googleClientId: string
  productVersion: string
}

export type ServerRuntimeConfig = TokenExchangeConfig & {
  cookieKey: string
}

export type RuntimeConfig = {
  server: ServerRuntimeConfig
  public: PublicRuntimeConfig
}

/**
 * Validates process configuration once at startup and keeps the private and
 * browser-visible portions distinct.
 */
export function loadRuntimeConfig(
  environment: Record<string, string | undefined>,
): RuntimeConfig {
  const publicClientId = requireEnvironment(
    environment,
    'VITE_GOOGLE_CLIENT_ID',
  )
  const serverClientId = requireEnvironment(environment, 'GOOGLE_CLIENT_ID')
  if (publicClientId !== serverClientId) {
    throw new Error('VITE_GOOGLE_CLIENT_ID must match GOOGLE_CLIENT_ID')
  }

  const cookieKey = requireEnvironment(environment, 'SESSION_COOKIE_KEY')
  if (!/^[0-9a-fA-F]{64}$/.test(cookieKey)) {
    throw new Error('SESSION_COOKIE_KEY must be 32 bytes (64 hex chars)')
  }

  return {
    server: {
      clientId: serverClientId,
      clientSecret: requireEnvironment(environment, 'GOOGLE_CLIENT_SECRET'),
      redirectUri: 'postmessage',
      cookieKey,
    },
    public: {
      googleClientId: publicClientId,
      productVersion: requireEnvironment(environment, 'APP_VERSION'),
    },
  }
}

/** Serializes only the explicitly public configuration as executable JS. */
export function serializePublicRuntimeConfig(
  config: PublicRuntimeConfig,
): string {
  const json = JSON.stringify(config)
    .replaceAll('&', '\\u0026')
    .replaceAll('<', '\\u003c')
    .replaceAll('>', '\\u003e')
    .replaceAll('\u2028', '\\u2028')
    .replaceAll('\u2029', '\\u2029')
  return `globalThis.__PLANNER_RUNTIME_CONFIG__=${json};`
}

function requireEnvironment(
  environment: Record<string, string | undefined>,
  name: string,
): string {
  const value = environment[name]
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`)
  }
  return value
}
