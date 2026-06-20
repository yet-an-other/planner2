import { useState } from 'react'
import { cn } from '@/lib/utils'

type AvatarProps = {
  /** Display name, used for the image alt text. */
  displayName: string
  /** Initials shown while the image loads, on load failure, or when there is no url. */
  initials: string
  /** Profile picture url. When null, the initials are shown with no image element. */
  pictureUrl: string | null
  /** Sizing/positioning applied to the circular container (e.g. `h-6 w-6`). */
  className?: string
}

type ImageLoadState = 'loading' | 'loaded' | 'error'

/**
 * A circular avatar that never shows a broken-image placeholder.
 *
 * The initials are always present underneath the image. The image sits on top
 * with opacity 0 until its `onLoad` fires (so it can still receive load/error
 * events), and is removed on `onError` so a failed or expired profile picture
 * falls back to the initials cleanly.
 */
export function Avatar({
  displayName,
  initials,
  pictureUrl,
  className,
}: AvatarProps) {
  const [imageState, setImageState] = useState<ImageLoadState>(
    pictureUrl ? 'loading' : 'error',
  )
  const [prevUrl, setPrevUrl] = useState(pictureUrl)

  // Reset load state when the picture url changes.
  if (prevUrl !== pictureUrl) {
    setPrevUrl(pictureUrl)
    setImageState(pictureUrl ? 'loading' : 'error')
  }

  const showImage = pictureUrl !== null && imageState !== 'error'

  return (
    <span
      className={cn(
        'relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full bg-[#777b60] text-[9px] font-extrabold tracking-[-0.04em] text-white sm:text-[10px]',
        className,
      )}
    >
      <span className="leading-none">{initials}</span>
      {showImage && (
        <img
          alt={`${displayName} profile`}
          className={cn(
            'absolute inset-0 h-full w-full object-cover transition-opacity',
            imageState === 'loaded' ? 'opacity-100' : 'opacity-0',
          )}
          onError={() => setImageState('error')}
          onLoad={() => setImageState('loaded')}
          src={pictureUrl ?? undefined}
        />
      )}
    </span>
  )
}
