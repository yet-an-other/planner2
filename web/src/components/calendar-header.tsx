import { LogIn, LogOut, UserRound } from 'lucide-react'
import { formatFullDate } from '@/lib/calendar-dates'
import { type GoogleAccountProfile } from '@/lib/google-account-connection'
import type { HeaderStatus } from '@/lib/use-google-account-connection'
import { Avatar } from './avatar'
import { PRODUCT_VERSION } from '@/lib/product-version'
import { cn } from '@/lib/utils'

const WEEKDAY_LABELS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

type CalendarHeaderProps = {
  /** Today, for the Today Jump button's accessible label. */
  today: Date
  /** The Visible Month label shown in the centre of the header. */
  visibleMonth: string
  /** Merged status from the connection and events modules for the Header Status area. */
  status: HeaderStatus | null
  /** Whether the Google Account Connection is currently connected. */
  connected: boolean
  /** True when a Google client id is configured and connect() will act. */
  isConfigured: boolean
  /** The connected profile, or null when disconnected. */
  profile: GoogleAccountProfile | null
  /** Return the Calendar Surface to Today. */
  onJumpToToday: () => void
  /** Begin the Google OAuth connect flow. */
  onConnect: () => void
  /** Revoke the token and disconnect. */
  onDisconnect: () => void
}

/**
 * The non-scrolling chrome above the Calendar Surface: the Product Name,
 * Product Version, Visible Month (with a Today Jump), the Account Control, the
 * Header Status area, and the Monday-first weekday labels.
 *
 * Presentational only — all state and actions are passed in.
 */
export function CalendarHeader({
  today,
  visibleMonth,
  status,
  connected,
  isConfigured,
  profile,
  onJumpToToday,
  onConnect,
  onDisconnect,
}: CalendarHeaderProps) {
  return (
    <header className="shrink-0 border-b border-[#d8d1bd] bg-[#f5f1e6] text-[#252819] shadow-sm">
      <div className="grid h-20 grid-cols-[auto_minmax(0,1fr)_auto] grid-rows-[minmax(0,1fr)_auto] items-center gap-x-2 px-1 pb-2 pt-1 sm:gap-x-4 sm:px-6">
        <div className="relative z-10 col-start-1 row-start-1 self-start justify-self-start whitespace-nowrap text-[clamp(18px,6vw,40px)] font-extrabold leading-none tracking-[-0.08em] text-[#777b60]">
          Planner
        </div>
        <div className="relative z-10 col-start-1 row-start-2 self-start justify-self-end text-[10px] font-medium leading-none tracking-[0.28em] text-[#8b8f72]">
          v{PRODUCT_VERSION}
        </div>
        <h1 className="relative z-0 col-start-1 col-end-4 row-start-1 min-w-0 whitespace-nowrap text-center text-[clamp(14px,4vw,26px)] font-extrabold tracking-tight">
          <button
            aria-label={`Return to Today, ${formatFullDate(today)}`}
            className="mx-auto block max-w-full truncate rounded-full px-2 py-2 transition-colors hover:bg-[#ebe4d2] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f] focus-visible:ring-offset-2 focus-visible:ring-offset-[#f5f1e6] sm:px-4"
            onClick={onJumpToToday}
            title="Return to Today"
            type="button"
          >
            {visibleMonth}
          </button>
        </h1>
        <div className="relative z-10 col-start-3 row-start-1 self-center justify-self-end">
          <AccountControl
            connected={connected}
            disabled={!isConfigured}
            profile={profile}
            onConnect={onConnect}
            onDisconnect={onDisconnect}
          />
        </div>
        <div
          aria-atomic="true"
          aria-live="polite"
          className={cn(
            'col-start-2 col-end-4 row-start-2 min-h-3 min-w-0 self-start truncate text-right text-[11px] font-medium leading-none',
            status?.tone === 'error' ? 'text-red-700' : 'text-[#7c8066]',
          )}
          role="status"
        >
          {status?.message ?? '\u00A0'}
        </div>
      </div>
      <div className="grid h-10 grid-cols-7 bg-[#e8e2d0] text-xs font-medium uppercase tracking-[0.2em] text-[#6f725a]">
        {WEEKDAY_LABELS.map((weekday, index) => (
          <div
            className={cn(
              'flex items-center justify-center',
              index >= 5 && 'bg-[#ded8c8]/50',
            )}
            key={weekday}
          >
            {weekday}
          </div>
        ))}
      </div>
    </header>
  )
}

type AccountControlProps = {
  connected: boolean
  disabled?: boolean
  profile: GoogleAccountProfile | null
  onConnect: () => void
  onDisconnect: () => void
}

function AccountControl({
  connected,
  disabled = false,
  profile,
  onConnect,
  onDisconnect,
}: AccountControlProps) {
  const displayText = connected && profile ? profile.displayName : 'Connect Google'
  const actionLabel = connected
    ? `Disconnect Google account for ${displayText}`
    : 'Connect Google account'
  const ActionIcon = connected ? LogOut : LogIn

  return (
    <button
      aria-label={actionLabel}
      className="inline-flex h-7 w-[62px] items-center justify-center gap-1.5 rounded-full border border-[#d8d1bd] bg-white/80 px-2 text-xs font-medium text-[#384052] shadow-sm transition-colors hover:bg-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#7d855f] focus-visible:ring-offset-2 focus-visible:ring-offset-[#f5f1e6] disabled:cursor-not-allowed disabled:opacity-60 sm:h-8 md:w-48 md:justify-start"
      disabled={disabled}
      onClick={connected ? onDisconnect : onConnect}
      title={actionLabel}
      type="button"
    >
      {connected && profile ? (
        <Avatar
          displayName={profile.displayName}
          initials={profile.initials}
          pictureUrl={profile.pictureUrl}
          className="-ml-1 h-5 w-5 sm:h-6 sm:w-6"
        />
      ) : (
        <span className="-ml-1 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-[#e5e7df] text-[#777b60] sm:h-6 sm:w-6">
          <UserRound aria-hidden="true" className="h-3.5 w-3.5" strokeWidth={2.4} />
        </span>
      )}
      <span className="hidden min-w-0 truncate md:block">{displayText}</span>
      <ActionIcon
        aria-hidden="true"
        className={cn(
          'ml-auto h-4 w-4 shrink-0',
          connected ? 'text-[#384052]' : 'text-[#777b60]',
        )}
        strokeWidth={2.4}
      />
    </button>
  )
}
