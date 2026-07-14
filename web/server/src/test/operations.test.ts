import { describe, expect, it, vi } from 'vitest'
import {
  createGracefulShutdown,
  createOperationalState,
  KUBERNETES_TERMINATION_GRACE_MS,
  SHUTDOWN_DEADLINE_MS,
  type GracefulServer,
  type ShutdownScheduler,
} from '../operations'

type FakeServer = GracefulServer & {
  completeClose(error?: Error): void
}

function createFakeServer(): FakeServer {
  let closeCallback: ((error?: Error) => void) | undefined
  return {
    close: vi.fn((callback: (error?: Error) => void) => {
      closeCallback = callback
    }),
    closeAllConnections: vi.fn(),
    completeClose: (error?: Error) => closeCallback?.(error),
  }
}

function createScheduler(): {
  schedule: ShutdownScheduler
  run(): void
  cancel: ReturnType<typeof vi.fn>
  delay(): number | undefined
} {
  let callback: (() => void) | undefined
  let scheduledDelay: number | undefined
  const cancel = vi.fn()
  return {
    schedule: (scheduledCallback, delayMs) => {
      callback = scheduledCallback
      scheduledDelay = delayMs
      return { cancel }
    },
    run: () => callback?.(),
    cancel,
    delay: () => scheduledDelay,
  }
}

describe('graceful shutdown', () => {
  it('stops readiness immediately and waits for the server to drain active requests', async () => {
    const operations = createOperationalState()
    operations.markReady()
    const server = createFakeServer()
    const scheduler = createScheduler()
    const shutdown = createGracefulShutdown({
      operations,
      server,
      schedule: scheduler.schedule,
    })
    let completed = false

    const completion = shutdown().then(() => {
      completed = true
    })
    await Promise.resolve()

    expect(operations.isReady()).toBe(false)
    expect(operations.status()).toBe('shutting-down')
    expect(server.close).toHaveBeenCalledOnce()
    expect(completed).toBe(false)

    server.completeClose()
    await completion

    expect(completed).toBe(true)
    expect(server.closeAllConnections).not.toHaveBeenCalled()
    expect(scheduler.cancel).toHaveBeenCalledOnce()
  })

  it('force-closes connections before the Kubernetes termination grace expires', async () => {
    const operations = createOperationalState()
    operations.markReady()
    const server = createFakeServer()
    const scheduler = createScheduler()
    const shutdown = createGracefulShutdown({
      operations,
      server,
      schedule: scheduler.schedule,
    })

    const completion = shutdown()
    scheduler.run()
    await completion

    expect(SHUTDOWN_DEADLINE_MS).toBeLessThan(KUBERNETES_TERMINATION_GRACE_MS)
    expect(scheduler.delay()).toBe(SHUTDOWN_DEADLINE_MS)
    expect(server.closeAllConnections).toHaveBeenCalledOnce()
  })
})
