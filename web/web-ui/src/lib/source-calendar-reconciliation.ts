import type { SourceCalendar } from './google-calendar-events'
import type { HeaderStatus } from './use-google-account-connection'

/**
 * Source Calendar Reconciliation (Planning glossary): the alignment of
 * Planner's Source Calendars and Selected Source Calendars with the
 * calendars currently available from Google. This module owns every
 * decision in that alignment — the eager list load on connect, the
 * picker-open refetch, selection persistence, and reconciliation with
 * its one-in-flight/one-queued serialization — as a pure reducer:
 * signals in, commands and resolutions out. The useSourceCalendars hook
 * executes the commands and settles reconcile promises from the
 * resolutions; storage crosses the seam as signal payload and command.
 */

/** Stable identifier for a Source Calendar (Google's calendar id). */
export type SourceCalendarId = string

/** Why a calendar-list fetch was started; each kind completes differently. */
type ListFetchKind = 'eager' | 'pickerOpen' | 'reconcile'

type ListFetch = {
  kind: ListFetchKind
  email: string
  epoch: number
}

export type SourceCalendarsState = {
  /** The live Source Calendar list as last loaded. */
  available: SourceCalendar[]
  /** The committed Selected Source Calendars, as Google calendar ids. */
  selectedIds: SourceCalendarId[]
  /** The list-loading failure status, when one is owed. */
  status: HeaderStatus | null
  /** Whether a list load for the control or picker is in flight. */
  isLoadingList: boolean
  /** Whether the Source Calendar Picker is presented. */
  pickerOpen: boolean
  /** The connected account's email, or `null` while disconnected. */
  connectedEmail: string | null
  /** The persisted selection read at connect, applied when the eager load lands. */
  persistedIdsOnConnect: SourceCalendarId[]
  /** Outstanding calendar-list fetches by their request id. */
  listFetches: Record<number, ListFetch>
  nextFetchId: number
  /** Monotonic marker of the latest connection decision: any fetch or
   * reconcile started before it changed resolves stale. */
  epoch: number
  /** The reconcile run owning the serialized seam, if any. */
  reconcileInFlight: { requestIds: number[]; fetchId: number; epoch: number } | null
  /** The one queued trailing reconcile run shared by later callers. */
  reconcileQueued: { requestIds: number[]; epoch: number } | null
  /** Batches invalidated by cancellation, keyed by their still-running
   * fetch: their callers resolve `[]` when the fetch settles, while new
   * reconcile requests start fresh runs immediately. */
  staleReconcileBatches: Record<number, number[]>
}

export type SourceCalendarsSignal =
  | { type: 'connected'; email: string; persistedIds: SourceCalendarId[] }
  | { type: 'disconnected' }
  | { type: 'listLoaded'; fetchId: number; list: SourceCalendar[] }
  | { type: 'listFailed'; fetchId: number }
  | { type: 'pickerOpenRequested' }
  | { type: 'pickerClosed' }
  | { type: 'selectionSaved'; ids: SourceCalendarId[] }
  | { type: 'reconcileRequested'; id: number }
  | { type: 'cancelPendingReconciliation' }

export type SourceCalendarsCommand =
  | { type: 'fetchList'; fetchId: number }
  | { type: 'persistSelection'; email: string; ids: SourceCalendarId[] }

/** The settlement of one reconcile request's promise: the reconciled
 * selection to refresh with, or `[]` when the request went stale. */
export type SourceCalendarsResolution = {
  id: number
  calendars: SourceCalendar[]
}

export type SourceCalendarsTransition = {
  state: SourceCalendarsState
  commands: SourceCalendarsCommand[]
  resolutions: SourceCalendarsResolution[]
}

const LIST_FAILED_STATUS: HeaderStatus = {
  message: 'Calendar list could not be loaded',
  tone: 'error',
}

export const initialSourceCalendarsState: SourceCalendarsState = {
  available: [],
  selectedIds: [],
  status: null,
  isLoadingList: false,
  pickerOpen: false,
  connectedEmail: null,
  persistedIdsOnConnect: [],
  listFetches: {},
  nextFetchId: 1,
  epoch: 0,
  reconcileInFlight: null,
  reconcileQueued: null,
  staleReconcileBatches: {},
}

/**
 * The default Selected Source Calendars before the user has chosen anything:
 * the primary calendar, or — if Google reports no primary — the first
 * available calendar so the surface is never empty (minimum-one).
 */
export function defaultSelectionIds(calendars: SourceCalendar[]): SourceCalendarId[] {
  const primary = calendars.find((calendar) => calendar.primary)
  if (primary) {
    return [primary.id]
  }
  return calendars.length > 0 ? [calendars[0].id] : []
}

/**
 * Reconciles a persisted selection against the live calendar list: keeps only
 * stored ids that are still available (dropping deleted or access-revoked
 * calendars), and falls back to the default selection when none survive — so a
 * stale or empty persisted selection can never leave the surface empty.
 */
export function reconcileSelection(
  storedIds: SourceCalendarId[],
  available: SourceCalendar[],
): SourceCalendarId[] {
  const availableIds = new Set(available.map((calendar) => calendar.id))
  const surviving = storedIds.filter((id) => availableIds.has(id))
  return surviving.length > 0 ? surviving : defaultSelectionIds(available)
}

export function handleSourceCalendars(
  state: SourceCalendarsState,
  signal: SourceCalendarsSignal,
): SourceCalendarsTransition {
  switch (signal.type) {
    case 'connected': {
      if (state.connectedEmail === signal.email) {
        return noop(state)
      }
      const fetchId = state.nextFetchId
      return {
        state: {
          ...state,
          connectedEmail: signal.email,
          persistedIdsOnConnect: signal.persistedIds,
          isLoadingList: true,
          epoch: state.epoch + 1,
          listFetches: {
            ...state.listFetches,
            [fetchId]: { kind: 'eager', email: signal.email, epoch: state.epoch + 1 },
          },
          nextFetchId: fetchId + 1,
        },
        commands: [{ type: 'fetchList', fetchId }],
        resolutions: [],
      }
    }

    case 'disconnected': {
      return {
        state: {
          ...state,
          available: [],
          selectedIds: [],
          status: null,
          isLoadingList: false,
          pickerOpen: false,
          connectedEmail: null,
          persistedIdsOnConnect: [],
          epoch: state.epoch + 1,
        },
        commands: [],
        resolutions: [],
      }
    }

    case 'listLoaded':
    case 'listFailed': {
      const fetch = state.listFetches[signal.fetchId]
      if (!fetch) {
        return noop(state)
      }
      const listFetches = { ...state.listFetches }
      delete listFetches[signal.fetchId]
      const stale =
        fetch.email !== state.connectedEmail || fetch.epoch !== state.epoch
      const isLoadingList = Object.values(listFetches).some(
        (entry) => entry.kind !== 'reconcile',
      )

      if (fetch.kind === 'reconcile') {
        const staleIds = state.staleReconcileBatches[signal.fetchId]
        if (staleIds) {
          const staleReconcileBatches = { ...state.staleReconcileBatches }
          delete staleReconcileBatches[signal.fetchId]
          return {
            state: { ...state, listFetches, staleReconcileBatches },
            commands: [],
            resolutions: staleIds.map((id) => ({ id, calendars: [] })),
          }
        }
        return completeReconcile(
          state,
          signal,
          signal.fetchId,
          listFetches,
          stale,
        )
      }
      if (stale) {
        return noop({ ...state, listFetches, isLoadingList })
      }
      if (signal.type === 'listFailed') {
        return {
          state: { ...state, listFetches, isLoadingList, status: LIST_FAILED_STATUS },
          commands: [],
          resolutions: [],
        }
      }
      if (fetch.kind === 'eager') {
        return {
          state: {
            ...state,
            listFetches,
            isLoadingList,
            available: signal.list,
            status: null,
            selectedIds: reconcileSelection(
              state.persistedIdsOnConnect,
              signal.list,
            ),
            persistedIdsOnConnect: [],
          },
          commands: [],
          resolutions: [],
        }
      }
      // pickerOpen
      return {
        state: {
          ...state,
          listFetches,
          isLoadingList,
          available: signal.list,
          status: null,
          pickerOpen: true,
        },
        commands: [],
        resolutions: [],
      }
    }

    case 'pickerOpenRequested': {
      if (!state.connectedEmail) {
        return noop(state)
      }
      const fetchId = state.nextFetchId
      return {
        state: {
          ...state,
          isLoadingList: true,
          listFetches: {
            ...state.listFetches,
            [fetchId]: {
              kind: 'pickerOpen',
              email: state.connectedEmail,
              epoch: state.epoch,
            },
          },
          nextFetchId: fetchId + 1,
        },
        commands: [{ type: 'fetchList', fetchId }],
        resolutions: [],
      }
    }

    case 'pickerClosed':
      return noop({ ...state, pickerOpen: false })

    case 'selectionSaved': {
      // Minimum-one: the picker disables Save at zero, so an empty draft
      // never reaches here; guard defensively regardless.
      if (signal.ids.length === 0) {
        return noop(state)
      }
      return {
        state: { ...state, selectedIds: signal.ids, pickerOpen: false },
        commands: state.connectedEmail
          ? [
              {
                type: 'persistSelection',
                email: state.connectedEmail,
                ids: signal.ids,
              },
            ]
          : [],
        resolutions: [],
      }
    }

    case 'reconcileRequested': {
      if (!state.connectedEmail) {
        return { state, commands: [], resolutions: [{ id: signal.id, calendars: [] }] }
      }
      if (state.reconcileInFlight) {
        if (state.reconcileQueued) {
          // A trailing run is already queued: later callers share it.
          return noop({
            ...state,
            reconcileQueued: {
              ...state.reconcileQueued,
              requestIds: [...state.reconcileQueued.requestIds, signal.id],
            },
          })
        }
        return noop({
          ...state,
          reconcileQueued: { requestIds: [signal.id], epoch: state.epoch },
        })
      }
      const fetchId = state.nextFetchId
      return {
        state: {
          ...state,
          listFetches: {
            ...state.listFetches,
            [fetchId]: {
              kind: 'reconcile',
              email: state.connectedEmail,
              epoch: state.epoch,
            },
          },
          nextFetchId: fetchId + 1,
          reconcileInFlight: {
            requestIds: [signal.id],
            fetchId,
            epoch: state.epoch,
          },
        },
        commands: [{ type: 'fetchList', fetchId }],
        resolutions: [],
      }
    }

    case 'cancelPendingReconciliation': {
      // New runs start fresh immediately; the cancelled batch resolves
      // `[]` when its physical fetch settles.
      const staleReconcileBatches = { ...state.staleReconcileBatches }
      if (state.reconcileInFlight) {
        staleReconcileBatches[state.reconcileInFlight.fetchId] = [
          ...state.reconcileInFlight.requestIds,
          ...(state.reconcileQueued?.requestIds ?? []),
        ]
      }
      return noop({
        ...state,
        epoch: state.epoch + 1,
        reconcileInFlight: null,
        reconcileQueued: null,
        staleReconcileBatches,
      })
    }
  }
}

function noop(state: SourceCalendarsState): SourceCalendarsTransition {
  return { state, commands: [], resolutions: [] }
}

/** Completes the reconcile run whose list fetch settled: applies a fresh
 * reconciliation, preserves the last known selection on failure, resolves
 * every caller of the run stale when the epoch moved, and drains the one
 * queued trailing run. */
function completeReconcile(
  state: SourceCalendarsState,
  signal: { type: 'listLoaded'; list: SourceCalendar[] } | { type: 'listFailed' },
  fetchId: number,
  listFetches: Record<number, ListFetch>,
  fetchStale: boolean,
): SourceCalendarsTransition {
  const inFlight = state.reconcileInFlight
  if (!inFlight || inFlight.fetchId !== fetchId) {
    return noop({ ...state, listFetches })
  }
  const stale = fetchStale || inFlight.epoch !== state.epoch
  const commands: SourceCalendarsCommand[] = []
  const resolutions: SourceCalendarsResolution[] = []
  let next: SourceCalendarsState = {
    ...state,
    listFetches,
    reconcileInFlight: null,
  }

  if (stale) {
    for (const id of inFlight.requestIds) {
      resolutions.push({ id, calendars: [] })
    }
  } else if (signal.type === 'listLoaded') {
    const nextIds = reconcileSelection(state.selectedIds, signal.list)
    next = {
      ...next,
      available: signal.list,
      selectedIds: nextIds,
      status: null,
    }
    if (state.connectedEmail) {
      commands.push({
        type: 'persistSelection',
        email: state.connectedEmail,
        ids: nextIds,
      })
    }
    const selected = signal.list.filter((calendar) =>
      nextIds.includes(calendar.id),
    )
    for (const id of inFlight.requestIds) {
      resolutions.push({ id, calendars: selected })
    }
  } else {
    // Failure is deliberately non-destructive: the last known selection is
    // returned so an event refresh can still proceed.
    const lastKnown = state.available.filter((calendar) =>
      state.selectedIds.includes(calendar.id),
    )
    next = { ...next, status: LIST_FAILED_STATUS }
    for (const id of inFlight.requestIds) {
      resolutions.push({ id, calendars: lastKnown })
    }
  }

  // Drain the one queued trailing run: start it against the current
  // epoch, or resolve it stale.
  const queued = next.reconcileQueued
  if (queued) {
    next = { ...next, reconcileQueued: null }
    if (queued.epoch !== next.epoch || !next.connectedEmail) {
      for (const id of queued.requestIds) {
        resolutions.push({ id, calendars: [] })
      }
    } else {
      const fetchId = next.nextFetchId
      next = {
        ...next,
        listFetches: {
          ...next.listFetches,
          [fetchId]: {
            kind: 'reconcile',
            email: next.connectedEmail,
            epoch: next.epoch,
          },
        },
        nextFetchId: fetchId + 1,
        reconcileInFlight: {
          requestIds: queued.requestIds,
          fetchId,
          epoch: queued.epoch,
        },
      }
      commands.push({ type: 'fetchList', fetchId })
    }
  }

  return { state: next, commands, resolutions }
}
