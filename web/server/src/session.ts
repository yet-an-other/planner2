import type { GoogleAccountProfile } from '@planner/web-contracts'

/** The encrypted payload owned by the web server's session cookie. */
export type Session = {
  accessToken: string
  /** Epoch milliseconds at which the access token expires. */
  accessTokenExpiresAt: number
  refreshToken: string
  profile: GoogleAccountProfile
}
