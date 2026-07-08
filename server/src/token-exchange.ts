import type { GoogleAccountProfile, Session } from '@planner/shared'

/** The token fields Google returns from an authorization-code exchange. */
export type GoogleTokensResponse = {
  access_token: string
  expires_in: number
  refresh_token?: string
  id_token: string
}

/** Server-side OAuth credentials used to exchange a code for tokens. */
export type TokenExchangeConfig = {
  clientId: string
  clientSecret: string
  /** `postmessage` for the GIS popup code-client flow. */
  redirectUri: string
}

/** Injectable Google HTTP call, so the exchange is unit-testable offline. */
export type TokenExchangeDeps = {
  postToGoogle: (body: URLSearchParams) => Promise<GoogleTokensResponse>
}

/**
 * Exchanges a one-time authorization code for a Session: posts the code (with
 * the server-side `client_secret`) to Google's token endpoint, then decodes the
 * profile from the returned `id_token`. The `access_type: 'offline'` /
 * `prompt: 'consent'` on the SPA's code-client request is what makes Google
 * return a `refresh_token` here.
 */
export async function exchangeAuthCode(
  code: string,
  config: TokenExchangeConfig,
  deps: TokenExchangeDeps,
): Promise<Session> {
  const body = new URLSearchParams({
    client_id: config.clientId,
    client_secret: config.clientSecret,
    grant_type: 'authorization_code',
    code,
    redirect_uri: config.redirectUri,
  })

  const tokens = await deps.postToGoogle(body)

  return {
    accessToken: tokens.access_token,
    accessTokenExpiresAt: Date.now() + tokens.expires_in * 1000,
    refreshToken: tokens.refresh_token ?? '',
    profile: decodeIdToken(tokens.id_token),
  }
}

/**
 * Decodes the profile from a Google `id_token` (a JWT) without verifying its
 * signature — the token arrives server-to-server over TLS from Google's own
 * token endpoint, so the transport is already authenticated. Signature
 * verification is a possible future hardening.
 */
export function decodeIdToken(idToken: string): GoogleAccountProfile {
  const payload = idToken.split('.')[1]
  const claims = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as {
    email?: string
    name?: string
    picture?: string
  }

  const email = claims.email ?? ''
  const displayName = claims.name ?? (email || 'Google User')

  return {
    email,
    displayName,
    initials: getInitials(displayName),
    pictureUrl: claims.picture ?? null,
  }
}

function getInitials(displayName: string) {
  const initials = displayName
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0])
    .join('')
    .toUpperCase()

  return initials || 'G'
}
