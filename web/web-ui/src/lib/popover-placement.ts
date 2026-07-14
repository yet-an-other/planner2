/**
 * Pure geometry for placing the Event Detail Popover. Given the trigger's
 * rect, the viewport size, and the popover's measured size, returns the
 * `top`/`left`/`width` that keep the popover fully on screen — clamping
 * horizontally and flipping above the trigger when below would overflow.
 *
 * Extracted from the component so the placement math (the part that actually
 * prevents off-screen cropping) is unit-testable without a layout engine.
 */

export type PopoverSide = 'below' | 'above'

export type PopoverPlacement = {
  /** Pixel offset from the top of the viewport. */
  top: number
  /** Pixel offset from the left of the viewport. */
  left: number
  /** Constrained popover width (never wider than the viewport allows). */
  width: number
  /** Which vertical side of the trigger the popover sits on. */
  side: PopoverSide
}

export type PopoverPlacementInput = {
  /** Rect of the element that triggered the popover, in viewport coordinates. */
  anchorRect: DOMRect
  viewport: { width: number; height: number }
  popover: { width: number; height: number }
  /** Minimum gap between the popover and any viewport edge. @default 8 */
  margin?: number
  /** Gap between the anchor and the popover. @default 8 */
  gap?: number
}

/**
 * Computes a placement that keeps the popover entirely within the viewport.
 *
 * - Horizontal: `left` is clamped to `[margin, viewport.width - width - margin]`,
 *   so a trigger near the right edge no longer pushes the popover off-screen.
 * - Vertical: the popover prefers to sit below the trigger; if that would
 *   overflow the bottom and there is room above, it flips above; if neither
 *   side fits fully, it is clamped inside the viewport and relies on the
 *   popover's own internal scroll for the overflow.
 */
export function computePopoverPlacement(
  input: PopoverPlacementInput,
): PopoverPlacement {
  const { anchorRect, viewport, popover } = input
  const margin = input.margin ?? 8
  const gap = input.gap ?? 8

  // --- Horizontal ---
  const width = Math.min(popover.width, Math.max(0, viewport.width - 2 * margin))
  const maxLeft = Math.max(margin, viewport.width - width - margin)
  const left = Math.min(Math.max(anchorRect.left, margin), maxLeft)

  // --- Vertical ---
  const belowTop = anchorRect.bottom + gap
  const aboveTop = anchorRect.top - gap - popover.height
  const fitsBelow = belowTop + popover.height <= viewport.height - margin
  const fitsAbove = aboveTop >= margin

  let top: number
  let side: PopoverSide
  if (fitsBelow) {
    top = belowTop
    side = 'below'
  } else if (fitsAbove) {
    top = aboveTop
    side = 'above'
  } else {
    // Neither side fits fully: pick the roomier side, then clamp inside.
    const spaceBelow = viewport.height - margin - belowTop
    const spaceAbove = anchorRect.top - gap - margin
    side = spaceBelow >= spaceAbove ? 'below' : 'above'
    top = side === 'below' ? belowTop : aboveTop
    const maxTop = Math.max(margin, viewport.height - popover.height - margin)
    top = Math.min(Math.max(top, margin), maxTop)
  }

  return {
    top: Math.round(top),
    left: Math.round(left),
    width: Math.round(width),
    side,
  }
}
