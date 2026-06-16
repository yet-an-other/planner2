export const GOOGLE_ACCOUNT_SCOPES = [
  'openid',
  'email',
  'profile',
  'https://www.googleapis.com/auth/calendar.readonly',
].join(' ')

export type GoogleAccountProfile = {
  displayName: string
  initials: string
  pictureUrl: string | null
}

type GoogleTokenResponse = {
  access_token?: string
  error?: string
  error_description?: string
}

type GoogleTokenClient = {
  requestAccessToken: (overrideConfig?: { prompt?: string }) => void
}

type GoogleIdentityServices = {
  accounts: {
    oauth2: {
      initTokenClient: (config: {
        client_id: string
        scope: string
        callback: (response: GoogleTokenResponse) => void
      }) => GoogleTokenClient
      revoke: (accessToken: string, done: () => void) => void
    }
  }
}

declare global {
  var google: GoogleIdentityServices | undefined
}

type GoogleUserInfo = {
  email?: string
  name?: string
  picture?: string
}

export function requestGoogleAccessToken(
  clientId: string,
  onTokenResponse: (response: GoogleTokenResponse) => void,
) {
  if (!globalThis.google?.accounts.oauth2) {
    throw new Error('Google Identity Services is not loaded')
  }

  const tokenClient = globalThis.google.accounts.oauth2.initTokenClient({
    client_id: clientId,
    scope: GOOGLE_ACCOUNT_SCOPES,
    callback: onTokenResponse,
  })

  tokenClient.requestAccessToken({ prompt: 'consent' })
}

export async function fetchGoogleAccountProfile(
  accessToken: string,
): Promise<GoogleAccountProfile> {
  const response = await fetch('https://www.googleapis.com/oauth2/v3/userinfo', {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  })

  if (!response.ok) {
    throw new Error('Google profile could not be loaded')
  }

  const userInfo = (await response.json()) as GoogleUserInfo
  const displayName = userInfo.name ?? userInfo.email ?? 'Google User'

  return {
    displayName,
    initials: getInitials(displayName),
    pictureUrl: userInfo.picture ?? null,
  }
}

export function revokeGoogleAccessToken(accessToken: string, done: () => void) {
  if (!globalThis.google?.accounts.oauth2) {
    done()
    return
  }

  globalThis.google.accounts.oauth2.revoke(accessToken, done)
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
