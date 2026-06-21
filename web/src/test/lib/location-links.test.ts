import { describe, expect, it } from 'vitest'
import { buildLocationHref } from '@/lib/location-links'

describe('buildLocationHref', () => {
  it('classifies a whole-string http(s) URL as a direct url link', () => {
    expect(buildLocationHref('https://zoom.us/j/123456')).toEqual({
      kind: 'url',
      url: 'https://zoom.us/j/123456',
    })
    expect(buildLocationHref('http://example.com/meet')).toEqual({
      kind: 'url',
      url: 'http://example.com/meet',
    })
  })

  it('classifies a place name as a Google Maps search link', () => {
    const href = buildLocationHref('ESCP Business School')
    expect(href.kind).toBe('maps')
    if (href.kind !== 'maps') return
    expect(href.url).toBe(
      'https://www.google.com/maps/search/?api=1&query=' +
        encodeURIComponent('ESCP Business School'),
    )
  })

  it('encodes a full multi-part address into the Maps search query', () => {
    const address =
      'ESCP Business School - Turin Campus, Via Andrea Doria, 27, 10123 Torino TO, Italy'
    const href = buildLocationHref(address)

    expect(href.kind).toBe('maps')
    if (href.kind !== 'maps') return
    expect(href.url).toBe(
      'https://www.google.com/maps/search/?api=1&query=' +
        encodeURIComponent(address),
    )
  })

  it('encodes reserved characters in the Maps query (#, spaces, commas)', () => {
    const href = buildLocationHref('Room #4, Floor 2')

    expect(href.kind).toBe('maps')
    if (href.kind !== 'maps') return
    expect(href.url).toBe(
      'https://www.google.com/maps/search/?api=1&query=' +
        encodeURIComponent('Room #4, Floor 2'),
    )
    expect(href.url).toContain(encodeURIComponent('#'))
  })

  it('collapses multi-line whitespace to single spaces before building the Maps URL', () => {
    const href = buildLocationHref('Line one\nLine two\n\nLine three')

    expect(href.kind).toBe('maps')
    if (href.kind !== 'maps') return
    expect(href.url).toBe(
      'https://www.google.com/maps/search/?api=1&query=' +
        encodeURIComponent('Line one Line two Line three'),
    )
  })

  it('treats a URL embedded in prose as a maps search of the whole string', () => {
    const prose = 'Join at https://example.com/meet'
    const href = buildLocationHref(prose)

    expect(href.kind).toBe('maps')
    if (href.kind !== 'maps') return
    expect(href.url).toBe(
      'https://www.google.com/maps/search/?api=1&query=' +
        encodeURIComponent(prose),
    )
  })

  it('treats a virtual marker like "Online" as a maps search, not a special case', () => {
    const href = buildLocationHref('Online')

    expect(href.kind).toBe('maps')
    if (href.kind !== 'maps') return
    expect(href.url).toBe(
      'https://www.google.com/maps/search/?api=1&query=' +
        encodeURIComponent('Online'),
    )
  })

  it('does not treat javascript: or mailto: schemes as url links', () => {
    expect(buildLocationHref('javascript:alert(1)').kind).toBe('maps')
    expect(buildLocationHref('mailto:organizer@example.com').kind).toBe('maps')
  })
})
