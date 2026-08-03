import type { SourceCalendarId } from './source-calendar-reconciliation'

/**
 * Per-device persistence of the Selected Source Calendars (web ADR 0003).
 * The selection is stored in `localStorage` as a JSON array of stable
 * Google calendar ids, keyed per Google account so two accounts in one
 * browser keep independent selections.
 *
 * This is the storage adapter behind Source Calendar Reconciliation: the
 * reducer in `source-calendar-reconciliation.ts` owns every persistence
 * decision and crosses this seam only as signal payload (reads at
 * connect) and command (writes on connect, reconcile, and save).
 */

const STORAGE_PREFIX = 'planner.sourceCalendars.'

/** The localStorage key for one account's persisted selection. */
export function sourceCalendarStorageKey(accountEmail: string): string {
  return `${STORAGE_PREFIX}${accountEmail}`
}

/**
 * Reads the persisted selection for an account. Returns an empty array when
 * nothing is stored or the value is unreadable/corrupt — never throws.
 */
export function loadPersistedSelection(accountEmail: string): SourceCalendarId[] {
  try {
    const raw = localStorage.getItem(sourceCalendarStorageKey(accountEmail))
    if (!raw) {
      return []
    }
    const parsed: unknown = JSON.parse(raw)
    if (!Array.isArray(parsed)) {
      return []
    }
    return parsed.filter((id): id is string => typeof id === 'string')
  } catch {
    return []
  }
}

/** Writes the selection for an account. Ignores storage failures (quota, etc.). */
export function persistSelection(
  accountEmail: string,
  ids: SourceCalendarId[],
): void {
  try {
    localStorage.setItem(
      sourceCalendarStorageKey(accountEmail),
      JSON.stringify(ids),
    )
  } catch {
    // Storage may be unavailable (private mode, quota); selection stays
    // session-only. Nothing to do.
  }
}
