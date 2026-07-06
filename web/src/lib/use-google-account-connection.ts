import { useCallback, useState } from 'react'
import {
  fetchGoogleAccountProfile,
  requestGoogleAccessToken,
  revokeGoogleAccessToken,
  type GoogleAccountProfile,
} from './google-account-connection'

/**
 * A status line for the Header Status area of the Calendar Surface.
 *
 * Owns the shared shape produced by the Google Account Connection lifecycle;
 * the render module merges it with events-related statuses.
 */
export type HeaderStatus = {
  message: string
  tone: 'info' | 'warning' | 'error'
}

/**
 * The state of the Google Account Connection: either connected with the token
 * and profile needed to fetch Calendar Events, or disconnected.
 */
export type GoogleAccountConnectionState =
  | { status: 'connected'; accessToken: string; profile: GoogleAccountProfile }
  | { status: 'disconnected' }

/**
 * The interface of the Google Account Connection module.
 */
export type GoogleAccountConnection = {
  /** The current connection state; token and profile are present when connected. */
  connection: GoogleAccountConnectionState
  /** True when a Google client id is configured and connect() will act. */
  isConfigured: boolean
  /** Status line from the connection lifecycle (includes the not-configured fallback). */
  status: HeaderStatus | null
  /** Begin the Google OAuth connect flow. No-op when not configured. */
  connect: () => void
  /** Revoke the token and disconnect. No-op when already disconnected. */
  disconnect: () => void
}

type GoogleTokenResponse = {
  access_token?: string
  error?: string
  error_description?: string
}

const NOT_CONFIGURED_STATUS: HeaderStatus = {
  message: 'Google client ID is not configured',
  tone: 'error',
}

/**
 * Owns the Google Account Connection lifecycle — token acquisition, profile
 * loading, disconnect, and the status messages those produce — behind a single
 * seam. The render module reads `connection`, `status`, and the actions without
 * knowing about Google Identity Services, token clients, or revocation.
 */
export function useGoogleAccountConnection(
  clientId: string,
): GoogleAccountConnection {
  const trimmedClientId = clientId.trim()
  const isConfigured = trimmedClientId.length > 0
  const [connection, setConnection] = useState<GoogleAccountConnectionState>({
    status: 'disconnected',
  })
  const [status, setStatus] = useState<HeaderStatus | null>(null)

  const handleTokenResponse = useCallback(
    async (response: GoogleTokenResponse) => {
      if (response.error) {
        setStatus({
          message: response.error_description ?? 'Google connection was cancelled',
          tone: 'error',
        })
        return
      }

      if (!response.access_token) {
        setStatus({
          message: 'Google connection did not return an access token',
          tone: 'error',
        })
        return
      }

      try {
        const profile = await fetchGoogleAccountProfile(response.access_token)

        setConnection({
          status: 'connected',
          accessToken: response.access_token,
          profile,
        })
        setStatus({ message: 'Google account connected', tone: 'info' })
      } catch (error) {
        setStatus({
          message: getErrorMessage(error, 'Google profile could not be loaded'),
          tone: 'error',
        })
      }
    },
    [],
  )

  const connect = useCallback(() => {
    if (!isConfigured) {
      return
    }

    setStatus({ message: 'Connecting Google account...', tone: 'info' })

    try {
      requestGoogleAccessToken(trimmedClientId, (response: GoogleTokenResponse) => {
        void handleTokenResponse(response)
      })
    } catch (error) {
      setStatus({
        message: getErrorMessage(error, 'Google connection is unavailable'),
        tone: 'error',
      })
    }
  }, [isConfigured, trimmedClientId, handleTokenResponse])

  const disconnect = useCallback(() => {
    if (connection.status !== 'connected') {
      return
    }

    revokeGoogleAccessToken(connection.accessToken, () => {
      setConnection({ status: 'disconnected' })
      setStatus({ message: 'Google account disconnected', tone: 'info' })
    })
  }, [connection])

  const statusWithFallback = status ?? (isConfigured ? null : NOT_CONFIGURED_STATUS)

  return {
    connection,
    isConfigured,
    status: statusWithFallback,
    connect,
    disconnect,
  }
}

function getErrorMessage(error: unknown, fallback: string) {
  return error instanceof Error ? error.message : fallback
}
