import { UnauthorizedError } from './google-calendar-events'

/**
 * Runs a Google-API-calling operation, refreshing the access token and retrying
 * exactly once if it fails with `UnauthorizedError` (a 401). Any other error
 * propagates unchanged. A second 401 on the retry is not retried again — the
 * refresh function is expected to update the connection's access token and
 * return the fresh value.
 */
export async function withTokenRefresh<T>(
  operation: (accessToken: string) => Promise<T>,
  accessToken: string,
  refresh: () => Promise<string>,
): Promise<T> {
  try {
    return await operation(accessToken)
  } catch (error) {
    if (!(error instanceof UnauthorizedError)) {
      throw error
    }
    const freshAccessToken = await refresh()
    return operation(freshAccessToken)
  }
}
