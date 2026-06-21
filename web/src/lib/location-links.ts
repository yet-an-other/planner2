/**
 * Presentation-only location linkification for the Event Detail Popover.
 *
 * The `location` data model stays a plain `string | null` (memory-only, per
 * ADR 0001/0002 — never persisted into Saved Busy Blocks); this module turns
 * that string into an actionable href computed at render time. Symmetric with
 * `text-links.ts` (the description seam).
 *
 * Two kinds:
 * - `url` — the entire location string is an `http(s)` URL (e.g. a pasted
 *   video-conference link). The string itself is the href; the popover renders
 *   it as a direct text link.
 * - `maps` — everything else (place names, addresses, fragments). The string
 *   becomes a Google Maps search query via the documented
 *   `search/?api=1&query=` URL, letting Maps geocode and interpret arbitrary
 *   free text. The popover renders a pin-icon link to this href plus the
 *   location as plain text.
 *
 * Only `http`/`https` whole-string URLs become `url` links. This deliberately
 * excludes `javascript:`/`mailto:` and URLs embedded in prose, so a malicious
 * location can never become a script URL and prose-with-a-URL honestly goes to
 * Maps search as a whole string.
 */

export type LocationHref =
  | { kind: 'maps'; url: string }
  | { kind: 'url'; url: string }

const GOOGLE_MAPS_SEARCH_BASE = 'https://www.google.com/maps/search/?api=1&query='

/** Whole-string http(s) URL: the trimmed value is exactly one URL, nothing else. */
const WHOLE_URL_PATTERN = /^https?:\/\/\S+$/i

/** Collapses runs of whitespace (including newlines) to a single space. */
function collapseWhitespace(value: string): string {
  return value.replace(/\s+/g, ' ').trim()
}

/**
 * Classifies a location string and builds its actionable href.
 *
 * @param location - a non-empty trimmed location string (the popover guards
 *   the null/empty cases before calling).
 */
export function buildLocationHref(location: string): LocationHref {
  if (WHOLE_URL_PATTERN.test(location)) {
    return { kind: 'url', url: location }
  }

  const query = encodeURIComponent(collapseWhitespace(location))
  return { kind: 'maps', url: `${GOOGLE_MAPS_SEARCH_BASE}${query}` }
}
