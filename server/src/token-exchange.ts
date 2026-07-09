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

/** Refresh a little before the access token actually expires, to avoid races. */
export const REFRESH_SKEW_MS = 60_000

export type RefreshResult =
  | { refreshed: false; session: Session }
  | { refreshed: true; session: Session }

/**
 * Returns the session unchanged while its access token is still valid (with a
 * small skew), otherwise refreshes it via the `refresh_token` grant. The
 * profile is carried over unchanged (it does not change on refresh). Detection
 * of a revoked grant (`invalid_grant`) is a separate slice.
 */
export async function refreshIfNeeded(
  session: Session,
  config: TokenExchangeConfig,
  deps: TokenExchangeDeps,
  now: number = Date.now(),
): Promise<RefreshResult> {
  if (now < session.accessTokenExpiresAt - REFRESH_SKEW_MS) {
    return { refreshed: false, session }
  }

  const body = new URLSearchParams({
    client_id: config.clientId,
    client_secret: config.clientSecret,
    grant_type: 'refresh_token',
    refresh_token: session.refreshToken,
  })

  const tokens = await deps.postToGoogle(body)

  return {
    refreshed: true,
    session: {
      accessToken: tokens.access_token,
      accessTokenExpiresAt: now + tokens.expires_in * 1000,
      refreshToken: tokens.refresh_token ?? session.refreshToken,
      profile: session.profile,
    },
  }
}

/** Injectable Google revocation call, so logout is unit-testable offline. */
export type RevokeDeps = {
  postToRevoke: (body: URLSearchParams) => Promise<void>
}

/**
 * Revokes the session's refresh token at Google (which also invalidates any
 * derived access token), severing the grant on explicit disconnect. No config
 * is needed — the revocation endpoint takes only the token.
 */
export async function revokeRefreshToken(
  session: Session,
  deps: RevokeDeps,
): Promise<void> {
  const body = new URLSearchParams({
    token: session.refreshToken,
    token_type_hint: 'refresh_token',
  })
  await deps.postToRevoke(body)
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
