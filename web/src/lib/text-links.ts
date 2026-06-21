/**
 * Presentation-only linkification for the Event Detail Popover description.
 *
 * The description data model stays plain text (HTML is stripped at
 * normalization — see `buildDescription`); this module splits that plain text
 * into text/link segments so the popover can render URLs as anchors without
 * ever storing or trusting raw HTML.
 *
 * Only `http`/`https` URLs are linkified. This deliberately excludes
 * `javascript:` and other schemes, so a malicious description cannot become a
 * script URL in the popover.
 */

export type TextSegment =
  | { kind: 'text'; value: string }
  | { kind: 'link'; value: string; url: string }

const URL_PATTERN = /https?:\/\/[^\s<>"')]+/g

/**
 * Splits `text` into an ordered list of text and link segments. A bare URL with
 * no surrounding text yields a single link segment. Empty input yields `[]`.
 */
export function splitTextIntoLinkSegments(text: string): TextSegment[] {
  if (!text) {
    return []
  }

  const segments: TextSegment[] = []
  let lastIndex = 0

  for (const match of text.matchAll(URL_PATTERN)) {
    const index = match.index ?? 0
    const url = match[0]

    if (index > lastIndex) {
      segments.push({ kind: 'text', value: text.slice(lastIndex, index) })
    }
    segments.push({ kind: 'link', value: url, url })
    lastIndex = index + url.length
  }

  if (lastIndex < text.length) {
    segments.push({ kind: 'text', value: text.slice(lastIndex) })
  }

  return segments
}
