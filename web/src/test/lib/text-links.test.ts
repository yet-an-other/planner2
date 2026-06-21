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

  it('keeps a Gmail "created from an email" URL fully intact including the query string', () => {
    const text =
      'This event was created from an email you received in Gmail. https://mail.google.com/mail?extsrc=cal&plid=ACUX6DMFTDX5QSW_x7zcvype_uzetpgxNqZ9HSs'
    const segments = splitTextIntoLinkSegments(text)

    expect(segments).toHaveLength(2)
    expect(segments[0]).toEqual({
      kind: 'text',
      value:
        'This event was created from an email you received in Gmail. ',
    })
    expect(segments[1]).toEqual({
      kind: 'link',
      value:
        'https://mail.google.com/mail?extsrc=cal&plid=ACUX6DMFTDX5QSW_x7zcvype_uzetpgxNqZ9HSs',
      url:
        'https://mail.google.com/mail?extsrc=cal&plid=ACUX6DMFTDX5QSW_x7zcvype_uzetpgxNqZ9HSs',
    })
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
