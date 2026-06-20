import { describe, expect, it } from 'vitest'
import {
  computeScrollTrigger,
  createFetchedWindow,
  extendFetchedWindow,
} from '@/lib/fetched-window'

describe('computeScrollTrigger', () => {
  const fetchedWindow = createFetchedWindow(
    new Date(2025, 0, 19), // earliest: Jan 19 2025
    new Date(2026, 11, 19), // latest: Dec 19 2026
  )

  it('returns no-op when the visible range is well inside the fetched window', () => {
    const visibleRange = {
      start: new Date(2026, 5, 1),
      end: new Date(2026, 5, 15),
    }

    expect(computeScrollTrigger(visibleRange, fetchedWindow)).toBe('no-op')
  })

  it('returns fetch-future when the visible range end reaches the future trigger zone', () => {
    // future boundary = latest - 1 month = Nov 19 2026
    const visibleRange = {
      start: new Date(2026, 11, 13),
      end: new Date(2026, 11, 19), // at latest
    }

    expect(computeScrollTrigger(visibleRange, fetchedWindow)).toBe('fetch-future')
  })

  it('returns fetch-future when the visible range end is beyond the future boundary', () => {
    const visibleRange = {
      start: new Date(2026, 11, 20),
      end: new Date(2026, 11, 26), // past latest already
    }

    expect(computeScrollTrigger(visibleRange, fetchedWindow)).toBe('fetch-future')
  })

  it('returns no-op just before the future trigger zone', () => {
    // future boundary = Nov 19 2026
    const visibleRange = {
      start: new Date(2026, 9, 1),
      end: new Date(2026, 10, 18), // Nov 18, one day before boundary
    }

    expect(computeScrollTrigger(visibleRange, fetchedWindow)).toBe('no-op')
  })

  it('returns fetch-past when the visible range start reaches the past trigger zone', () => {
    // past boundary = earliest + 1 month = Feb 19 2025
    const visibleRange = {
      start: new Date(2025, 0, 19), // at earliest
      end: new Date(2025, 0, 25),
    }

    expect(computeScrollTrigger(visibleRange, fetchedWindow)).toBe('fetch-past')
  })

  it('returns fetch-past when the visible range start is beyond the past boundary', () => {
    const visibleRange = {
      start: new Date(2024, 11, 1), // before earliest already
      end: new Date(2024, 11, 7),
    }

    expect(computeScrollTrigger(visibleRange, fetchedWindow)).toBe('fetch-past')
  })

  it('returns no-op just after the past trigger zone', () => {
    // past boundary = Feb 19 2025
    const visibleRange = {
      start: new Date(2025, 1, 20), // Feb 20, one day after boundary
      end: new Date(2025, 2, 5),
    }

    expect(computeScrollTrigger(visibleRange, fetchedWindow)).toBe('no-op')
  })

  it('prefers fetch-future when the visible range is within both trigger zones', () => {
    // A tiny window where both edges are within the buffer of a single visible week.
    const tinyWindow = createFetchedWindow(
      new Date(2026, 5, 10),
      new Date(2026, 5, 30),
    )
    const visibleRange = {
      start: new Date(2026, 5, 18),
      end: new Date(2026, 5, 22),
    }

    expect(computeScrollTrigger(visibleRange, tinyWindow)).toBe('fetch-future')
  })

  it('returns no-op at the future edge when the window has reached the calendar range end', () => {
    const calendarRange = {
      start: new Date(2025, 0, 19),
      end: new Date(2026, 11, 19),
    }
    const windowAtEdge = createFetchedWindow(
      new Date(2025, 0, 19),
      new Date(2026, 11, 19), // latest == calendar range end
    )
    const visibleRange = {
      start: new Date(2026, 11, 1),
      end: new Date(2026, 11, 19), // within the future trigger zone
    }

    expect(
      computeScrollTrigger(visibleRange, windowAtEdge, undefined, calendarRange),
    ).toBe('no-op')
  })

  it('returns no-op at the past edge when the window has reached the calendar range start', () => {
    const calendarRange = {
      start: new Date(2025, 0, 19),
      end: new Date(2026, 11, 19),
    }
    const windowAtEdge = createFetchedWindow(
      new Date(2025, 0, 19), // earliest == calendar range start
      new Date(2026, 11, 19),
    )
    const visibleRange = {
      start: new Date(2025, 0, 19), // within the past trigger zone
      end: new Date(2025, 0, 25),
    }

    expect(
      computeScrollTrigger(visibleRange, windowAtEdge, undefined, calendarRange),
    ).toBe('no-op')
  })

  it('still fetches when the window has not reached the calendar range edge', () => {
    const calendarRange = {
      start: new Date(2025, 0, 19),
      end: new Date(2026, 11, 19),
    }
    const windowWithRoom = createFetchedWindow(
      new Date(2025, 0, 19),
      new Date(2026, 10, 19), // latest well before calendar range end
    )
    const visibleRange = {
      start: new Date(2026, 10, 1),
      end: new Date(2026, 10, 19), // within the future trigger zone
    }

    expect(
      computeScrollTrigger(visibleRange, windowWithRoom, undefined, calendarRange),
    ).toBe('fetch-future')
  })
})

describe('extendFetchedWindow', () => {
  it('extends the latest edge forward for the future direction', () => {
    const window = createFetchedWindow(new Date(2026, 0, 19), new Date(2026, 5, 19))

    const extended = extendFetchedWindow(window, 'future', 3)

    expect(extended.latest).toEqual(new Date(2026, 8, 19)) // Sep 19 2026
    expect(extended.earliest).toEqual(window.earliest)
  })

  it('extends the earliest edge backward for the past direction', () => {
    const window = createFetchedWindow(new Date(2026, 0, 19), new Date(2026, 5, 19))

    const extended = extendFetchedWindow(window, 'past', 3)

    expect(extended.earliest).toEqual(new Date(2025, 9, 19)) // Oct 19 2025
    expect(extended.latest).toEqual(window.latest)
  })

  it('does not mutate the original window', () => {
    const window = createFetchedWindow(new Date(2026, 0, 19), new Date(2026, 5, 19))

    extendFetchedWindow(window, 'future', 3)

    expect(window.latest).toEqual(new Date(2026, 5, 19))
  })

  it('clamps the day when the target month is shorter', () => {
    const window = createFetchedWindow(new Date(2026, 0, 31), new Date(2026, 0, 31))

    const extended = extendFetchedWindow(window, 'future', 1)

    expect(extended.latest).toEqual(new Date(2026, 1, 28)) // Jan 31 + 1 month = Feb 28
  })

  describe('with a calendar range', () => {
    const calendarRange = {
      start: new Date(2025, 11, 1), // Dec 1 2025
      end: new Date(2026, 11, 31), // Dec 31 2026
    }

    it('clamps a future extension to the calendar range end', () => {
      // latest Nov 19 2026 + 3 months would be Feb 19 2027, overshooting the end.
      const window = createFetchedWindow(
        new Date(2026, 0, 19),
        new Date(2026, 10, 19),
      )

      const extended = extendFetchedWindow(
        window,
        'future',
        3,
        calendarRange,
      )

      expect(extended.latest).toEqual(calendarRange.end)
      expect(extended.earliest).toEqual(window.earliest)
    })

    it('clamps a past extension to the calendar range start', () => {
      // earliest Feb 19 2026 - 3 months would be Nov 19 2025, overshooting the start.
      const window = createFetchedWindow(
        new Date(2026, 1, 19),
        new Date(2026, 11, 19),
      )

      const extended = extendFetchedWindow(
        window,
        'past',
        3,
        calendarRange,
      )

      expect(extended.earliest).toEqual(calendarRange.start)
      expect(extended.latest).toEqual(window.latest)
    })

    it('does not clamp when the extension stays within the range', () => {
      const window = createFetchedWindow(
        new Date(2026, 2, 1),
        new Date(2026, 4, 1),
      )

      const extended = extendFetchedWindow(
        window,
        'future',
        1,
        calendarRange,
      )

      expect(extended.latest).toEqual(new Date(2026, 5, 1)) // Jun 1, within range
    })
  })
})
