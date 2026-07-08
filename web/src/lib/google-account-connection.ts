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

/** POSTs the authorization code to the backend; returns the decoded profile. */
export async function postAuthCallback(
  code: string,
): Promise<GoogleAccountProfile> {
  const response = await fetch('/api/auth/callback', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code }),
  })

  if (!response.ok) {
    throw new Error('Google connection could not be completed')
  }

  return ((await response.json()) as AuthCallbackResponse).profile
}

/** Reads a fresh access token from the backend (same-origin, cookie-authed). */
export async function fetchAccessToken(): Promise<string> {
  const response = await fetch('/api/token')

  if (!response.ok) {
    throw new Error('Google access token could not be loaded')
  }

  return ((await response.json()) as TokenResponse).accessToken
}

/**
 * Revokes the access token at Google. Used by disconnect in this slice; a later
 * slice replaces disconnect with a full `/api/logout` (revoke + clear cookie).
 */
export function revokeGoogleAccessToken(accessToken: string, done: () => void) {
  if (!globalThis.google?.accounts.oauth2) {
    done()
    return
  }

  globalThis.google.accounts.oauth2.revoke(accessToken, done)
}
