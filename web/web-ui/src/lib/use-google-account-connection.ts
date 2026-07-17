import { useCallback, useEffect, useRef, useState } from 'react'
import {
  deleteGoogleAccountConnection,
  fetchAccessToken,
  postAuthCallback,
  requestGoogleAuthorizationCode,
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
  /** Disconnect on This Device by deleting only this browser profile's
   * backend session. Rejects without changing connection state when deletion
   * fails. No-op when already disconnected. */
  disconnect: () => Promise<void>
  /**
   * Refreshes the access token from the backend (which refreshes server-side if
   * the cached token is stale) and returns it. Used by the 401-retry path so a
   * mid-session token expiry does not force a reconnect.
   */
  refreshAccessToken: () => Promise<string>
}

type GoogleCodeResponse = {
  code?: string
  error?: string
  error_description?: string
}

const NOT_CONFIGURED_STATUS: HeaderStatus = {
  message: 'Google client ID is not configured',
  tone: 'error',
}

/**
 * Owns the Google Account Connection lifecycle behind a single seam.
 *
 * On mount it attempts a silent restore from the backend's session cookie via
 * `/api/token` — so a returning user stays connected across reloads with no
 * popup or consent screen. `connect` runs the GIS code-client flow: obtain a
 * one-time code, POST it to `/api/auth/callback` (which exchanges it and sets
 * the encrypted session cookie), then read the access token back.
 * `refreshAccessToken` backs the 401-retry path for mid-session token expiry.
 * The profile comes from the `id_token` via the backend, so there is no
 * separate `userinfo` call.
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

  // Silent restore on mount: rehydrate the connection from the session cookie.
  // Runs at most once (the ref survives StrictMode's double-invoke of effects).
  const restoreRef = useRef(false)
  useEffect(() => {
    if (!isConfigured || restoreRef.current) {
      return
    }
    restoreRef.current = true
    let cancelled = false
    void (async () => {
      try {
        const { accessToken, profile } = await fetchAccessToken()
        if (!cancelled) {
          setConnection({ status: 'connected', accessToken, profile })
        }
      } catch {
        // No session (401) or a transient network error: leave the default
        // disconnected state. Restore is silent so it never clobbers a status
        // set by an explicit Connect or Disconnect on This Device.
      }
    })()
    return () => {
      cancelled = true
    }
  }, [isConfigured])

  const handleCodeResponse = useCallback(
    async (response: GoogleCodeResponse) => {
      if (response.error) {
        setStatus({
          message:
            response.error_description ?? 'Google connection was cancelled',
          tone: 'error',
        })
        return
      }

      if (!response.code) {
        setStatus({
          message: 'Google connection did not return an authorization code',
          tone: 'error',
        })
        return
      }

      try {
        const { accessToken, profile } = await postAuthCallback(response.code)
        setConnection({ status: 'connected', accessToken, profile })
        setStatus({ message: 'Google account connected', tone: 'info' })
      } catch (error) {
        setStatus({
          message: getErrorMessage(error, 'Google connection failed'),
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
      requestGoogleAuthorizationCode(trimmedClientId, (response) => {
        void handleCodeResponse(response)
      })
    } catch (error) {
      setStatus({
        message: getErrorMessage(error, 'Google connection is unavailable'),
        tone: 'error',
      })
    }
  }, [isConfigured, trimmedClientId, handleCodeResponse])

  const refreshAccessToken = useCallback(async (): Promise<string> => {
    try {
      const { accessToken, profile } = await fetchAccessToken()
      setConnection({ status: 'connected', accessToken, profile })
      return accessToken
    } catch {
      // Session gone (revoked grant or expired cookie): disconnect gracefully
      // so the surface falls back to Saved Busy Blocks rather than erroring.
      setConnection({ status: 'disconnected' })
      throw new Error('Google access token could not be loaded')
    }
  }, [])

  const disconnect = useCallback(async () => {
    if (connection.status !== 'connected') {
      return
    }

    setStatus({ message: 'Disconnecting on this device…', tone: 'info' })
    try {
      await deleteGoogleAccountConnection()
    } catch (error) {
      setStatus({
        message: 'Could not disconnect Google account on this device. Try again',
        tone: 'error',
      })
      throw error
    }
    setConnection({ status: 'disconnected' })
    setStatus({
      message: 'Google account disconnected on this device',
      tone: 'info',
    })
  }, [connection])

  const statusWithFallback = status ?? (isConfigured ? null : NOT_CONFIGURED_STATUS)

  return {
    connection,
    isConfigured,
    status: statusWithFallback,
    connect,
    disconnect,
    refreshAccessToken,
  }
}

function getErrorMessage(error: unknown, fallback: string) {
  return error instanceof Error ? error.message : fallback
}
