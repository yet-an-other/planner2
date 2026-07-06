import type { SourceCalendar } from './google-calendar-events'
import type { SourceCalendarId } from './use-source-calendars'

/**
 * Per-device persistence of the Selected Source Calendars (ADR 0003). The
 * selection is stored in `localStorage` as a JSON array of stable Google
 * calendar ids, keyed per Google account so two accounts in one browser keep
 * independent selections.
 *
 * This is the codebase's first persistence. The reconcile logic is pure and
 * tested independently of storage; the load/persist helpers are thin wrappers.
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

/**
 * The default Selected Source Calendars before the user has chosen anything: the
 * primary calendar, or — if Google reports no primary — the first available
 * calendar so the surface is never empty (minimum-one).
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
 *
 * Pure: no storage access, no side effects.
 */
export function reconcileSelection(
  storedIds: SourceCalendarId[],
  available: SourceCalendar[],
): SourceCalendarId[] {
  const availableIds = new Set(available.map((calendar) => calendar.id))
  const surviving = storedIds.filter((id) => availableIds.has(id))
  return surviving.length > 0 ? surviving : defaultSelectionIds(available)
}
