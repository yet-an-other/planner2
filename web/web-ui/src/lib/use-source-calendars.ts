import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  fetchCalendarList as fetchCalendarListFromGoogle,
  type SourceCalendar,
} from './google-calendar-events'
import type { GoogleAccountConnectionState } from './use-google-account-connection'
import {
  loadPersistedSelection,
  persistSelection,
} from './source-calendar-selection'
import {
  handleSourceCalendars,
  initialSourceCalendarsState,
  type SourceCalendarId,
  type SourceCalendarsCommand,
  type SourceCalendarsSignal,
  type SourceCalendarsState,
} from './source-calendar-reconciliation'

export type { SourceCalendarId } from './source-calendar-reconciliation'

/** Loads the Source Calendar list using a connected access token. */
export type FetchCalendarList = (accessToken: string) => Promise<SourceCalendar[]>

type UseSourceCalendarsParams = {
  connection: GoogleAccountConnectionState
  /** Injected so tests can drive the calendar-list fetch without the network. */
  fetchCalendarList?: FetchCalendarList
}

/**
 * Owns the user's Source Calendars: the available calendar list (loaded eagerly
 * on connect and refetched whenever the picker reopens), the Selected Source
 * Calendars (defaulting to the primary calendar), the picker's open state, and
 * the list-loading/error status. Calendar Event fetching consumes the resolved
 * `selectionCalendars`.
 *
 * Every decision lives in Source Calendar Reconciliation
 * (`source-calendar-reconciliation.ts`); this hook is the React adapter
 * that feeds it signals, executes its fetch and persistence commands,
 * and settles reconcile promises from its resolutions.
 */
export function useSourceCalendars({
  connection,
  fetchCalendarList = fetchCalendarListFromGoogle,
}: UseSourceCalendarsParams) {
  const [state, setState] = useState<SourceCalendarsState>(
    initialSourceCalendarsState,
  )
  const stateRef = useRef(state)
  const accessTokenRef = useRef<string | null>(null)
  accessTokenRef.current =
    connection.status === 'connected' ? connection.accessToken : null
  const deferredsRef = useRef(
    new Map<number, (calendars: SourceCalendar[]) => void>(),
  )
  const reconcileRequestRef = useRef(0)

  const feedRef = useRef<(signal: SourceCalendarsSignal) => void>(() => {})

  const execute = useCallback(
    (command: SourceCalendarsCommand) => {
      switch (command.type) {
        case 'fetchList': {
          const accessToken = accessTokenRef.current
          if (!accessToken) {
            return
          }
          fetchCalendarList(accessToken)
            .then((list) =>
              feedRef.current({
                type: 'listLoaded',
                fetchId: command.fetchId,
                list,
              }),
            )
            .catch(() =>
              feedRef.current({ type: 'listFailed', fetchId: command.fetchId }),
            )
          return
        }
        case 'persistSelection':
          persistSelection(command.email, command.ids)
          return
      }
    },
    [fetchCalendarList],
  )

  const feed = useCallback(
    (signal: SourceCalendarsSignal) => {
      const { state: next, commands, resolutions } = handleSourceCalendars(
        stateRef.current,
        signal,
      )
      stateRef.current = next
      setState(next)
      for (const resolution of resolutions) {
        const resolve = deferredsRef.current.get(resolution.id)
        if (resolve) {
          deferredsRef.current.delete(resolution.id)
          resolve(resolution.calendars)
        }
      }
      for (const command of commands) {
        execute(command)
      }
    },
    [execute],
  )
  feedRef.current = feed

  // Connection publications drive the machine: connect starts the eager
  // list load (with the persisted selection as payload), disconnect
  // clears everything.
  const connectionEmail =
    connection.status === 'connected' ? connection.profile.email : null
  useEffect(() => {
    if (connection.status === 'connected') {
      feed({
        type: 'connected',
        email: connection.profile.email,
        persistedIds: loadPersistedSelection(connection.profile.email),
      })
    } else {
      feed({ type: 'disconnected' })
    }
  }, [connection.status, connectionEmail, feed])

  const openPicker = useCallback(
    () => feed({ type: 'pickerOpenRequested' }),
    [feed],
  )
  const closePicker = useCallback(
    () => feed({ type: 'pickerClosed' }),
    [feed],
  )
  const saveSelection = useCallback(
    (ids: SourceCalendarId[]) => feed({ type: 'selectionSaved', ids }),
    [feed],
  )

  const reconcileCalendars = useCallback((): Promise<SourceCalendar[]> => {
    const id = ++reconcileRequestRef.current
    const promise = new Promise<SourceCalendar[]>((resolve) => {
      deferredsRef.current.set(id, resolve)
    })
    feed({ type: 'reconcileRequested', id })
    return promise
  }, [feed])

  const cancelPendingReconciliation = useCallback(
    () => feed({ type: 'cancelPendingReconciliation' }),
    [feed],
  )

  const selectionCalendars = useMemo(
    () =>
      state.available.filter((calendar) =>
        state.selectedIds.includes(calendar.id),
      ),
    [state.available, state.selectedIds],
  )

  return {
    available: state.available,
    selectionCalendars,
    status: state.status,
    isLoadingList: state.isLoadingList,
    pickerOpen: state.pickerOpen,
    openPicker,
    closePicker,
    saveSelection,
    reconcileCalendars,
    cancelPendingReconciliation,
  }
}
