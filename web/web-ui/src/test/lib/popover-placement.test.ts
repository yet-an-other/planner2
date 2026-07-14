import { describe, expect, it } from 'vitest'
import { computePopoverPlacement } from '@/lib/popover-placement'

/** Minimal DOMRect stand-in for deterministic placement tests. */
function rect(overrides: Partial<DOMRect> = {}): DOMRect {
  return {
    bottom: 100,
    left: 50,
    top: 80,
    right: 70,
    height: 20,
    width: 20,
    x: 50,
    y: 80,
    toJSON: () => ({}),
    ...overrides,
  } as DOMRect
}

const MARGIN = 8
const GAP = 8

describe('computePopoverPlacement', () => {
  it('places below and left-aligned when there is plenty of room', () => {
    const placement = computePopoverPlacement({
      anchorRect: rect({ bottom: 100, left: 50, top: 80 }),
      viewport: { width: 1280, height: 800 },
      popover: { width: 360, height: 200 },
      margin: MARGIN,
      gap: GAP,
    })

    expect(placement.side).toBe('below')
    expect(placement.top).toBe(108) // bottom (100) + gap (8)
    expect(placement.left).toBe(50)
  })

  it('clamps left so a right-edge trigger never overflows the viewport', () => {
    // Trigger hugs the right edge; popover (360 wide) would run off-screen.
    const placement = computePopoverPlacement({
      anchorRect: rect({ bottom: 100, left: 1000, top: 80 }),
      viewport: { width: 1280, height: 800 },
      popover: { width: 360, height: 200 },
      margin: MARGIN,
      gap: GAP,
    })

    expect(placement.left).toBe(912) // 1280 - 360 - 8
    // Right edge stays inside the viewport.
    expect(placement.left + 360).toBeLessThanOrEqual(1280 - MARGIN)
  })

  it('clamps left to the margin when the trigger is at or past the left edge', () => {
    const placement = computePopoverPlacement({
      anchorRect: rect({ bottom: 100, left: -5, top: 80 }),
      viewport: { width: 1280, height: 800 },
      popover: { width: 360, height: 200 },
      margin: MARGIN,
      gap: GAP,
    })

    expect(placement.left).toBe(MARGIN)
  })

  it('flips above when below would overflow but above has room', () => {
    // Trigger near the bottom: below (108 + 200 = 308... wait use small viewport)
    const placement = computePopoverPlacement({
      anchorRect: rect({ bottom: 500, left: 50, top: 480 }),
      viewport: { width: 800, height: 600 },
      popover: { width: 360, height: 200 },
      margin: MARGIN,
      gap: GAP,
    })

    // belowTop (508) + height (200) = 708 > 600 - 8, so it does not fit below.
    // aboveTop = 480 - 8 - 200 = 272 >= 8, so it fits above.
    expect(placement.side).toBe('above')
    expect(placement.top).toBe(272)
  })

  it('clamps within the viewport when the popover fits on neither side', () => {
    // Tiny viewport, tall popover: nowhere fits fully.
    const placement = computePopoverPlacement({
      anchorRect: rect({ bottom: 150, left: 50, top: 130 }),
      viewport: { width: 400, height: 300 },
      popover: { width: 200, height: 280 },
      margin: MARGIN,
      gap: GAP,
    })

    // The popover must remain within the viewport bounds top/bottom.
    expect(placement.top).toBeGreaterThanOrEqual(MARGIN)
    expect(placement.top + 280).toBeLessThanOrEqual(300 - MARGIN)
  })

  it('shrinks width and clamps left when the popover is wider than the viewport', () => {
    const placement = computePopoverPlacement({
      anchorRect: rect({ bottom: 100, left: 50, top: 80 }),
      viewport: { width: 300, height: 600 },
      popover: { width: 360, height: 200 },
      margin: MARGIN,
      gap: GAP,
    })

    // Width constrained so the popover fits with margin on both sides.
    expect(placement.width).toBe(300 - 2 * MARGIN)
    expect(placement.left).toBe(MARGIN)
    expect(placement.left + placement.width).toBeLessThanOrEqual(300 - MARGIN)
  })
})
