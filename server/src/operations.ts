export const KUBERNETES_TERMINATION_GRACE_MS = 30_000
export const SHUTDOWN_DEADLINE_MS = 25_000

export type OperationalStatus = 'starting' | 'ready' | 'shutting-down'

export type OperationalState = {
  status(): OperationalStatus
  isReady(): boolean
  markReady(): void
  beginShutdown(): void
}

export type GracefulServer = {
  close(callback: (error?: Error) => void): void
  closeAllConnections?(): void
}

export type ShutdownTimer = {
  cancel(): void
}

export type ShutdownScheduler = (
  callback: () => void,
  delayMs: number,
) => ShutdownTimer

type GracefulShutdownOptions = {
  operations: OperationalState
  server: GracefulServer
  schedule?: ShutdownScheduler
  deadlineMs?: number
}

/** Process-local lifecycle state shared by health checks and signal handling. */
export function createOperationalState(): OperationalState {
  let status: OperationalStatus = 'starting'

  return {
    status: () => status,
    isReady: () => status === 'ready',
    markReady: () => {
      if (status === 'starting') status = 'ready'
    },
    beginShutdown: () => {
      status = 'shutting-down'
    },
  }
}

/**
 * Stops readiness and new connection acceptance, then waits for active requests.
 * Remaining connections are force-closed before Kubernetes sends SIGKILL.
 */
export function createGracefulShutdown({
  operations,
  server,
  schedule = scheduleShutdown,
  deadlineMs = SHUTDOWN_DEADLINE_MS,
}: GracefulShutdownOptions): () => Promise<void> {
  if (deadlineMs >= KUBERNETES_TERMINATION_GRACE_MS) {
    throw new Error('Shutdown deadline must be below Kubernetes termination grace')
  }

  let completion: Promise<void> | undefined

  return () => {
    completion ??= new Promise<void>((resolve, reject) => {
      operations.beginShutdown()
      let settled = false
      let timer: ShutdownTimer | undefined

      const finish = (error?: Error) => {
        if (settled) return
        settled = true
        timer?.cancel()
        if (error) reject(error)
        else resolve()
      }

      timer = schedule(() => {
        server.closeAllConnections?.()
        finish()
      }, deadlineMs)

      try {
        server.close(finish)
      } catch (error) {
        finish(error instanceof Error ? error : new Error(String(error)))
      }
    })

    return completion
  }
}

function scheduleShutdown(callback: () => void, delayMs: number): ShutdownTimer {
  const timer = setTimeout(callback, delayMs)
  timer.unref()
  return { cancel: () => clearTimeout(timer) }
}
