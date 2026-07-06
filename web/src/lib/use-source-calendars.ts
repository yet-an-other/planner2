import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  fetchCalendarList as fetchCalendarListFromGoogle,
  type SourceCalendar,
} from './google-calendar-events'
import type {
  GoogleAccountConnectionState,
  HeaderStatus,
} from './use-google-account-connection'
import {
  loadPersistedSelection,
  persistSelection,
  reconcileSelection,
} from './source-calendar-selection'

/** Stable identifier for a Source Calendar (Google's calendar id). */
export type SourceCalendarId = string

/** Loads the Source Calendar list using a connected access token. */
export type FetchCalendarList = (accessToken: string) => Promise<SourceCalendar[]>

const LIST_FAILED_STATUS: HeaderStatus = {
  message: 'Calendar list could not be loaded',
  tone: 'error',
}

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
 * Selection is session-only in this module; persistence is a separate concern.
 */
export function useSourceCalendars({
  connection,
  fetchCalendarList = fetchCalendarListFromGoogle,
}: UseSourceCalendarsParams) {
  const [available, setAvailable] = useState<SourceCalendar[]>([])
  const [selectedIds, setSelectedIds] = useState<SourceCalendarId[]>([])
  const [status, setStatus] = useState<HeaderStatus | null>(null)
  const [isLoadingList, setIsLoadingList] = useState(false)
  const [pickerOpen, setPickerOpen] = useState(false)

  // Adjust state during render when the connection transitions. This is the
  // React "adjust state when a prop changes" pattern: on connect we start the
  // list-loading indicator, on disconnect we clear everything.
  const [prevStatus, setPrevStatus] = useState(connection.status)
  if (connection.status !== prevStatus) {
    setPrevStatus(connection.status)
    if (connection.status === 'connected') {
      setIsLoadingList(true)
    } else {
      setAvailable([])
      setSelectedIds([])
      setStatus(null)
      setIsLoadingList(false)
      setPickerOpen(false)
    }
  }

  // Fetches the calendar list. All setState calls sit after the await, so this
  // is safe to call from an effect (no synchronous setState in the effect body).
  // A failed refetch keeps the previously-loaded list rather than wiping it.
  const refreshList = useCallback(
    async (accessToken: string) => {
      try {
        const calendars = await fetchCalendarList(accessToken)
        setAvailable(calendars)
        setStatus(null)
        return calendars
      } catch {
        setStatus(LIST_FAILED_STATUS)
        return []
      } finally {
        setIsLoadingList(false)
      }
    },
    [fetchCalendarList],
  )

  // Eagerly load the calendar list on connect and default the selection to the
  // primary calendar (so the surface behaves as before until the user chooses).
  // setState lives only in the async callbacks; the injected fetch is external
  // so the react-hooks/set-state-in-effect rule is satisfied.
  useEffect(() => {
    if (connection.status !== 'connected') {
      return
    }
    const accountEmail = connection.profile.email
    let cancelled = false
    fetchCalendarList(connection.accessToken)
      .then((calendars) => {
        if (cancelled) {
          return
        }
        setAvailable(calendars)
        setStatus(null)
        setSelectedIds(
          reconcileSelection(loadPersistedSelection(accountEmail), calendars),
        )
      })
      .catch(() => {
        if (cancelled) {
          return
        }
        setStatus(LIST_FAILED_STATUS)
      })
      .finally(() => {
        if (!cancelled) {
          setIsLoadingList(false)
        }
      })
    return () => {
      cancelled = true
    }
  }, [connection, fetchCalendarList])

  const openPicker = useCallback(() => {
    if (connection.status !== 'connected') {
      return
    }
    setPickerOpen(true)
    // Refetch so calendars added or removed in another tab since connecting
    // become pickable without reconnecting.
    setIsLoadingList(true)
    void refreshList(connection.accessToken)
  }, [connection, refreshList])

  const closePicker = useCallback(() => setPickerOpen(false), [])

  const saveSelection = useCallback(
    (ids: SourceCalendarId[]) => {
      // Minimum-one: the picker disables Save at zero, so an empty draft never
      // reaches here; guard defensively regardless.
      if (ids.length === 0) {
        return
      }
      if (connection.status === 'connected') {
        persistSelection(connection.profile.email, ids)
      }
      setSelectedIds(ids)
      setPickerOpen(false)
    },
    [connection],
  )

  const selectionCalendars = useMemo(
    () => available.filter((calendar) => selectedIds.includes(calendar.id)),
    [available, selectedIds],
  )

  return {
    available,
    selectionCalendars,
    status,
    isLoadingList,
    pickerOpen,
    openPicker,
    closePicker,
    saveSelection,
  }
}
