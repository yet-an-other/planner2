import { describe, expect, it } from 'vitest'
import { getContrastTextColor } from './text-contrast'

describe('getContrastTextColor', () => {
  it('returns white for dark colors', () => {
    expect(getContrastTextColor('#000000')).toBe('#FFFFFF')
    expect(getContrastTextColor('#2952a3')).toBe('#FFFFFF')
    expect(getContrastTextColor('#0d7377')).toBe('#FFFFFF')
  })

  it('returns black for light colors', () => {
    expect(getContrastTextColor('#FFFFFF')).toBe('#000000')
    expect(getContrastTextColor('#F6BF26')).toBe('#000000')
    expect(getContrastTextColor('#E4D7F4')).toBe('#000000')
  })
})
