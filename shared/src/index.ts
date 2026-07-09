/**
 * The user's Google identity, decoded once from the Google `id_token` at
 * authorization-code exchange and carried (encrypted) in the session cookie.
 * Shared between the backend (which decodes it) and the SPA (which renders it
 * in the Account Control). See CONTEXT.md and ADR 0005.
 */
export type GoogleAccountProfile = {
  email: string
  displayName: string
  initials: string
  pictureUrl: string | null
}

/**
 * The encrypted payload of the session cookie. The backend owns this; the SPA
 * only consumes the `accessToken` (via `/api/token`) and the `profile`.
 */
export type Session = {
  accessToken: string
  /** Epoch milliseconds at which the access token expires. */
  accessTokenExpiresAt: number
  refreshToken: string
  profile: GoogleAccountProfile
}

/** Request body for `POST /api/auth/callback`. */
export type AuthCallbackRequest = {
  code: string
}

/** Response body for `POST /api/auth/callback`. The access token is returned
 * here so the SPA can connect in a single round-trip; `/api/token` is then
 * used only for silent restore and refresh. */
export type AuthCallbackResponse = {
  accessToken: string
  profile: GoogleAccountProfile
}

/** Response body for `GET /api/token`. The profile is included so the SPA can
 * restore the Account Control from the (HttpOnly) session cookie on load. */
export type TokenResponse = {
  accessToken: string
  profile: GoogleAccountProfile
}
