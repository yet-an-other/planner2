import type {
  AuthCallbackResponse,
  GoogleAccountProfile,
  TokenResponse,
} from '@planner/shared'

// The canonical GoogleAccountProfile type lives in @planner/shared so the
// backend (which decodes it from the id_token) and the SPA share one contract.
export type { GoogleAccountProfile }

export const GOOGLE_ACCOUNT_SCOPES = [
  'openid',
  'email',
  'profile',
  'https://www.googleapis.com/auth/calendar.readonly',
].join(' ')

type GoogleCodeResponse = {
  code?: string
  error?: string
  error_description?: string
}

type GoogleCodeClient = {
  requestCode: (overrideConfig?: { prompt?: string }) => void
}

type GoogleIdentityServices = {
  accounts: {
    oauth2: {
      initCodeClient: (config: {
        client_id: string
        scope: string
        access_type: 'offline'
        prompt: string
        callback: (response: GoogleCodeResponse) => void
      }) => GoogleCodeClient
      revoke: (accessToken: string, done: () => void) => void
    }
  }
}

declare global {
  var google: GoogleIdentityServices | undefined
}

/**
 * Opens the Google consent popup to obtain a one-time authorization code.
 * `access_type: 'offline'` + `prompt: 'consent'` are what make Google issue a
 * refresh token, which the backend later exchanges (and holds in the cookie).
 * The code is then POSTed to `/api/auth/callback`.
 */
export function requestGoogleAuthorizationCode(
  clientId: string,
  onCodeResponse: (response: GoogleCodeResponse) => void,
) {
  if (!globalThis.google?.accounts.oauth2) {
    throw new Error('Google Identity Services is not loaded')
  }

  const codeClient = globalThis.google.accounts.oauth2.initCodeClient({
    client_id: clientId,
    scope: GOOGLE_ACCOUNT_SCOPES,
    access_type: 'offline',
    prompt: 'consent',
    callback: onCodeResponse,
  })

  codeClient.requestCode()
}

/** POSTs the authorization code to the backend; returns the access token and
 * decoded profile (the backend exchanges the code and sets the session cookie). */
export async function postAuthCallback(
  code: string,
): Promise<AuthCallbackResponse> {
  const response = await fetch('/api/auth/callback', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code }),
  })

  if (!response.ok) {
    throw new Error('Google connection could not be completed')
  }

  return (await response.json()) as AuthCallbackResponse
}

/** Reads a fresh access token (and profile) from the backend — same-origin,
 * cookie-authed. Used on load to restore the connection and to refresh an
 * expired access token (the backend refreshes server-side as needed). */
export async function fetchAccessToken(): Promise<TokenResponse> {
  const response = await fetch('/api/token')

  if (!response.ok) {
    throw new Error('Google access token could not be loaded')
  }

  return (await response.json()) as TokenResponse
}

/** POSTs to the backend to revoke the Google grant and clear the session
 * cookie. Best-effort on the client: the caller clears the local connection
 * regardless, so a transient server failure still logs the user out here. */
export async function postLogout(): Promise<void> {
  const response = await fetch('/api/logout', { method: 'POST' })

  if (!response.ok) {
    throw new Error('Google disconnect failed')
  }
}
