# Persist Stored Calendar Events on iOS

## Status

Accepted. Supersedes ADR 0003, whose memory-only Calendar Events decision this reverses.

## Context

ADR 0003 kept iOS Calendar Events strictly memory-only: fetched per process run, never written to disk, with a disconnected or cold-offline surface presenting the bare Calendar Grid plus an iOS Header Status message. That decision bet that a mobile device is relaunched so frequently that persisted events have low value, and it protected a strict data-minimization App Privacy posture.

Two drivers proved that bet wrong:

- **Real offline usage.** Users open Planner while genuinely offline — travel, flights, poor connectivity — and a bare grid is unacceptable for a calendar app whose core value is showing the user's schedule.
- **Cold-launch experience even when online.** Every process start presented an empty grid until the initial fetch completed. Presenting Stored Calendar Events immediately and refreshing behind them removes that dead interval.

The Web Experience already persists Saved Busy Blocks (web ADR 0001) — timing and color without titles — but iOS needs full event fidelity: a placeholder without a title is not a usable offline schedule.

## Decision

The iOS Experience persists **Stored Calendar Events**: a per-Google-account, device-local copy of the Fetched Window's Calendar Events.

- **Content.** The full normalized Calendar Event model exactly as the surface renders it — title, timing, Event Color, location, notes, attendees, and Google link. Raw Google API payloads are never persisted.
- **Volume.** The store mirrors the Fetched Window. Entries falling out of the window, and events from deselected Source Calendars, disappear on the next write — no separate eviction policy.
- **Freshness.** Not persisted. Stored Calendar Events are presented at process start and treated as always stale; when connected, the existing per-process freshness pipeline fetches as if coverage were empty, and Calendar Event Refresh replaces the stored view atomically. Deletions and moves made elsewhere while offline surface only on the next successful refresh — accepted as the honest semantic of a read-only last-known-good mirror.
- **Writes.** Write-through: every successful initial, slab, or Calendar Event Refresh response updates the store with the in-memory model, so a crash or force-quit never resurrects events older than the last successful response.
- **Lifecycle.** Disconnect on This Device wipes the store. The store is excluded from backups (`NSURLIsExcludedFromBackupKey`): events live only on the device that fetched them and are re-derivable from Google.
- **Storage.** Application Support with Data Protection class Complete Until First User Authentication — never purged by the system (unlike Caches), encrypted against a powered-off or never-unlocked device, and not foreclosing future background refresh.

## Consequences

- Planner's iOS data-minimization stance narrows: the App Privacy story can no longer state that no Calendar data is stored. Privacy disclosures, App Store privacy answers, and the build-gate description in the Calendar Surface spec must be updated, and the Google-compliance research revisited, before release.
- The Calendar Surface spec's memory-only, bare-grid-offline, and no-persisted-freshness sections are rewritten to the Stored Calendar Events semantics above.
- The Web and iOS offline stories now differ in fidelity rather than in kind: Busy Blocks (timing and color, no title) on Web, full events on iOS. Parity work should consider whether Web adopts full events or iOS's stance is documented as the deliberate richer one.
- "Disconnect on This Device" retains true data-removal semantics: reconnecting an account refetches everything.

## Considered options

- **Persist Saved Busy Blocks for iOS (web parity).** Rejected: a title-less placeholder is not a usable offline schedule, and the driver is full offline fidelity, not merely preserving the grid's shape. Parity in kind is achieved by both platforms persisting *something*; fidelity parity was not the goal.
- **Keep Calendar Events memory-only (ADR 0003, status quo).** Rejected: both drivers above are real usage, and the "frequently relaunched, therefore low value" bet confused launch frequency with launch experience — frequent relaunch makes the empty-grid problem *more* common, not the persistence less valuable.
- **Persist freshness metadata with the store.** Rejected: the only case it serves is relaunch within five minutes of process death — exactly where iOS most often keeps the process alive — while a stale "fresh" flag surviving a long gap is a persistent bug source. Disk is always-stale; freshness stays per-process.
- **Flush to disk on backgrounding instead of write-through.** Rejected: force-quit and crash lose the latest fetches, silently showing the user older events than they last saw.
- **Caches directory.** Rejected: iOS purges Caches under storage pressure, defeating the feature precisely for the storage-constrained offline user.
- **Include the store in backups.** Rejected: backup carries full event titles, notes, and attendees into iCloud and onto other devices for one launch's worth of convenience on a new device.
