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
 *
 * Google's Gmail boilerplate ("This event was created from an email you
 * received in Gmail. https://mail.google.com/...") is recognized specially:
 * the trailing URL is collapsed into a labeled link on the word "Gmail" so the
 * raw URL is never shown as visible text.
 */

export type TextSegment =
  | { kind: 'text'; value: string }
  | { kind: 'link'; value: string; url: string }

/** Generic http(s) URL, stopping at the first whitespace or bracketing char. */
const URL_PATTERN = /https?:\/\/[^\s<>"')]+/

/**
 * Google's "created from an email you received in Gmail" line. The lead text
 * and the trailing `mail.google.com` URL are captured so the URL becomes the
 * href of a link whose visible label is "Gmail".
 */
const GMAIL_BOILERPLATE_PATTERN =
  /(This event was created from an email you received in )Gmail\.\s*(https:\/\/mail\.google\.com\/[^\s<>"')]+)/

/**
 * Splits `text` into an ordered list of text and link segments. Empty input
 * yields `[]`.
 *
 * Single pass, left to right: at each position the next Gmail boilerplate (if
 * any) or the next generic URL wins by earliest position, so the two kinds can
 * interleave freely and neither double-counts the other.
 */
export function splitTextIntoLinkSegments(text: string): TextSegment[] {
  if (!text) {
    return []
  }

  const segments: TextSegment[] = []
  let cursor = 0

  const pushText = (value: string) => {
    if (!value) {
      return
    }
    const previous = segments[segments.length - 1]
    if (previous && previous.kind === 'text') {
      previous.value += value
    } else {
      segments.push({ kind: 'text', value })
    }
  }

  while (cursor < text.length) {
    const rest = text.slice(cursor)

    const gmailMatch = rest.match(GMAIL_BOILERPLATE_PATTERN)
    const gmailStart = gmailMatch?.index ?? Number.POSITIVE_INFINITY

    const urlMatch = rest.match(URL_PATTERN)
    const urlStart = urlMatch?.index ?? Number.POSITIVE_INFINITY

    // No more tokens: flush the remainder as text and stop.
    if (gmailStart === Number.POSITIVE_INFINITY && urlStart === Number.POSITIVE_INFINITY) {
      pushText(rest)
      break
    }

    if (gmailStart <= urlStart) {
      const [, lead, url] = gmailMatch!
      pushText(rest.slice(0, gmailStart))
      pushText(lead)
      segments.push({ kind: 'link', value: 'Gmail', url })
      pushText('.')
      cursor += gmailStart + gmailMatch![0].length
    } else {
      const url = urlMatch![0]
      pushText(rest.slice(0, urlStart))
      segments.push({ kind: 'link', value: url, url })
      cursor += urlStart + url.length
    }
  }

  return segments
}
