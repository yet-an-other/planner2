import { describe, expect, it } from 'vitest'
import { splitTextIntoLinkSegments } from '@/lib/text-links'

describe('splitTextIntoLinkSegments', () => {
  it('returns a single text segment when there are no URLs', () => {
    expect(splitTextIntoLinkSegments('Quarterly planning')).toEqual([
      { kind: 'text', value: 'Quarterly planning' },
    ])
  })

  it('returns an empty array for empty input', () => {
    expect(splitTextIntoLinkSegments('')).toEqual([])
  })

  it('detects a bare URL as a single link segment', () => {
    const url = 'https://mail.google.com/mail?extsrc=cal&plid=ACUX6DMFTDX5QSW_x7zcvype_uzetpgxNqZ9HSs'
    expect(splitTextIntoLinkSegments(url)).toEqual([
      { kind: 'link', value: url, url },
    ])
  })

  it('collapses the Gmail "created from an email" URL into a clickable "Gmail" word, hiding the raw URL', () => {
    const url =
      'https://mail.google.com/mail?extsrc=cal&plid=ACUX6DMFTDX5QSW_x7zcvype_uzetpgxNqZ9HSs'
    const text = `This event was created from an email you received in Gmail. ${url}`
    const segments = splitTextIntoLinkSegments(text)

    expect(segments).toEqual([
      {
        kind: 'text',
        value: 'This event was created from an email you received in ',
      },
      { kind: 'link', value: 'Gmail', url },
      { kind: 'text', value: '.' },
    ])
    // The raw mail.google.com URL must never appear as visible text.
    expect(
      segments.some((segment) => segment.value.includes('mail.google.com')),
    ).toBe(false)
  })

  it('linkifies a generic URL that is not the Gmail boilerplate as a bare link', () => {
    const segments = splitTextIntoLinkSegments('See https://example.com/page now')

    expect(segments).toEqual([
      { kind: 'text', value: 'See ' },
      { kind: 'link', value: 'https://example.com/page', url: 'https://example.com/page' },
      { kind: 'text', value: ' now' },
    ])
  })

  it('splits text with a URL in the middle into three segments', () => {
    const segments = splitTextIntoLinkSegments('See https://example.com/page for details')

    expect(segments).toEqual([
      { kind: 'text', value: 'See ' },
      { kind: 'link', value: 'https://example.com/page', url: 'https://example.com/page' },
      { kind: 'text', value: ' for details' },
    ])
  })

  it('detects multiple URLs in the same text', () => {
    const segments = splitTextIntoLinkSegments(
      'First https://a.com then https://b.com',
    )

    expect(segments.map((s) => s.kind)).toEqual([
      'text',
      'link',
      'text',
      'link',
    ])
  })
})
