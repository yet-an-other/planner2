/**
 * The user's Google identity returned by the web server and rendered by the
 * Web Experience's Account Control. See `product/CONTEXT.md` and web ADR 0005.
 */
export type GoogleAccountProfile = {
  email: string
  displayName: string
  initials: string
  pictureUrl: string | null
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
