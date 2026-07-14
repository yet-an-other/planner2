import { describe, expect, it, vi } from 'vitest'
import { withTokenRefresh } from '@/lib/with-token-refresh'
import { UnauthorizedError } from '@/lib/google-calendar-events'

describe('withTokenRefresh', () => {
  it('retries once after a refresh when the operation is unauthorized (401)', async () => {
    const operation = vi
      .fn<(token: string) => Promise<string>>()
      .mockRejectedValueOnce(new UnauthorizedError())
      .mockResolvedValueOnce('result')
    const refresh = vi.fn().mockResolvedValue('fresh-token')

    const result = await withTokenRefresh(operation, 'stale-token', refresh)

    expect(result).toBe('result')
    expect(operation).toHaveBeenCalledTimes(2)
    expect(operation).toHaveBeenNthCalledWith(1, 'stale-token')
    expect(operation).toHaveBeenNthCalledWith(2, 'fresh-token')
    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('does not loop: a second 401 propagates after a single retry', async () => {
    const operation = vi
      .fn<(token: string) => Promise<string>>()
      .mockRejectedValue(new UnauthorizedError())
    const refresh = vi.fn().mockResolvedValue('fresh-token')

    await expect(
      withTokenRefresh(operation, 'stale-token', refresh),
    ).rejects.toBeInstanceOf(UnauthorizedError)
    expect(operation).toHaveBeenCalledTimes(2)
    expect(refresh).toHaveBeenCalledTimes(1)
  })

  it('propagates non-401 errors without refreshing', async () => {
    const error = new Error('network down')
    const operation = vi.fn().mockRejectedValue(error)
    const refresh = vi.fn()

    await expect(withTokenRefresh(operation, 'token', refresh)).rejects.toBe(error)
    expect(operation).toHaveBeenCalledTimes(1)
    expect(refresh).not.toHaveBeenCalled()
  })
})
