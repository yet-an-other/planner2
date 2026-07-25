# Planner for iOS and iPadOS

This directory is Planner's self-contained native delivery stack. It builds a universal SwiftUI app for iPhone and iPad and shares no executable code or build tooling with [`web/`](../web/).

## Requirements

- macOS with the full Xcode 26.6 application installed at `/Applications/Xcode.app`
- The iOS 18.5 Simulator runtime for the documented test destination
- No package manager or project generator. The single reviewed third-party package, Google Sign-In for iOS 9.2.0, resolves through Swift Package Manager with the exact version and dependency graph pinned in [`Planner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`](Planner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved); the SDK's privacy manifests ship with the package. No Google credentials are needed to build, test, or run

The application deployment target remains iOS/iPadOS 17.0. The locally installed runtimes do not include iOS 17, so execution on an actual iOS 17 runtime remains a required pre-release check.

## Open and run

From the repository root:

```sh
open ios/Planner.xcodeproj
```

Select the shared **Planner** scheme and an iPhone or iPad Simulator. A new process opens Today's Week Row at the top. The app supports iPhone portrait and landscape, all iPad orientations, Split View, and Stage Manager in one non-persistent scene.

Simulator builds and tests do not require a development team. To run on a physical device, choose a personal team in your local Xcode settings; do not commit that team to the project.

## Google connection release gate

The iOS Account Control and iOS Header Status sit behind a build-time release gate that stays **off** in every committed configuration: the app then initializes no connection behavior and the iOS Calendar Header keeps its accepted 100-point form. The gate remains off for production until a Calendar-data feature provides visible value for the sensitive scope. That feature has landed behind the same gate: Calendar Events on the iOS Calendar Surface, described below.

To enable the connection in a development build, copy [`Configurations/GoogleConnection.local.xcconfig.example`](Configurations/GoogleConnection.local.xcconfig.example) to `Configurations/GoogleConnection.local.xcconfig` (git-ignored) and supply the environment-specific inputs: the iOS OAuth client ID, its reversed form (the OAuth callback URL scheme), and the public HTTPS Privacy Policy URL. With the gate on, missing or invalid values leave the iOS Calendar Surface usable, disable Connect, and report “Google connection is not configured” in the iOS Header Status. Planner accepts no Google client secret: an installed app cannot keep one, so no such setting exists.

A configured development build restores a saved connection silently at launch — entering a restoring presentation instead of flashing a false Connect, refreshing expired credentials through Google Sign-In, and clearing confirmed-invalid authorization with reconnect guidance — and runs one Connect flow for Google identity and read-only Calendar access through the official Google Sign-In SDK. The current first-Connect explanation states that Planner reads events from Selected Source Calendars, stores their IDs on this device, stores no Calendar Events, and cannot modify Google Calendar. An account restored from an older disclosure stays connected but loads no Calendar data until the revised explanation is acknowledged; dismissal preserves Disconnect on This Device and offers the review again on the next foreground entry. A connected session survives offline periods with a recoverable warning and revalidates when connectivity returns or the app becomes active; only confirmed invalidation disconnects. An installation boundary correlates an install-local marker with a non-migrating Keychain device marker, so a reinstall or a backup restored to new hardware clears stale sign-in state and selections locally, while ordinary relaunches, updates, device restarts, and Disconnect on This Device retain the account's selection. The connected control shows the account avatar — profile image once loaded, initials otherwise — with the display name only when the measured width fits, and one activation disconnects on this device through local SDK sign-out only, never SDK disconnect or Google revocation, so sibling Planner connections stay intact. Planner persists no tokens or account profile data itself; Google Sign-In owns credential storage.

### Real-OAuth prerequisites (external, not committed)

The committed configuration contains no Google credentials and the repository never will: exercising a real Connect requires external setup in the shared Google Cloud project, documented as release gates rather than completed work:

1. Enable the **Google Calendar API** in the project.
2. Create an **iOS OAuth client** bound to Planner's bundle identifier; note its client ID and reversed client ID (the callback scheme).
3. Configure the OAuth consent screen; production use with the sensitive `calendar.readonly` scope requires Google's verification as applicable.
4. Publish a public **HTTPS Privacy Policy URL** covering current and intended Calendar-data handling.
5. Supply the three values plus `PLANNER_GOOGLE_CONNECTION_ENABLED = YES` in `Configurations/GoogleConnection.local.xcconfig` (git-ignored) and rebuild.

App Privacy answers must cover Planner's and the SDK's account and Calendar data behavior before distribution. The production gate stays off until the external release inputs are complete. Calendar Events and the internal Source Calendar restoration path have landed behind the gate; disclosure version 3 covers account-linked Selected Source Calendar IDs. The package graph, privacy manifests, and acceptance matrix live in [`docs/specs/google-account-connection.md`](docs/specs/google-account-connection.md).

### Calendar Events behind the release gate

After disclosure acknowledgement, a configured, connected development build loads complete readable Source Calendars, restores and reconciles the account's persisted selection, and presents Calendar Events from that selection on the iOS Calendar Surface. First use remains Primary-only (or uses the first deterministic readable Source Calendar when Google marks none as Primary); the connected iOS Source Calendar Control opens a native anchored picker that adapts to a compact sheet, persists immediate toggles, and atomically reloads every selected source around the visible dates after dismissal: all-day and multiday events as colored bars spanning their Date Cells, intraday events as dotted rows with a localized start time, dense days capped at four slots with a "+N more" Events Overflow marker that summons the read-only Day Events Popover — a native anchored popover adapting on compact widths to a half-height sheet, listing the Date Cell's complete ordered events (bars in lane order, then rows by start time) under a date heading, opened from memory with no network call. An open Day Events Popover reconciles live with refreshed events — edits and moves update items in place, deletions and declines remove them, a failed refresh leaves the list unchanged — and it dismisses itself when the day empties or on Disconnect on This Device. Events are fetched directly from the Google Calendar API — never through Planner's backend — starting with a window of Today ± 3 months and extending by two-month slabs as scrolling approaches the fetched edge. The iOS Header Status reports fetch progress, failures, and offline conditions; an offline launch leaves the bare grid with a warning and retries when connectivity returns. Events are memory-only: nothing is persisted, Disconnect on This Device clears them immediately, and Date Cells otherwise stay inert. Tapping a bar or row summons the read-only Event Detail Popover — a native anchored popover adapting on compact widths to a full-width, canvas-colored sheet that starts at half height and can expand — presenting the event's title with its Event Color accent and a localized timing line; scrolling and the Today Jump remain the only other product interactions. When connected Planner returns to the foreground after events have loaded, it silently performs a Calendar Event Refresh for the visible dates and a one-month buffer on each side, clipped to the Fetched Window. While the scene stays foreground-active, Planner repeats that refresh five minutes after the preceding Calendar Event request attempt completes; it cancels the pending interval while inactive or disconnected and resumes through the immediate foreground refresh. Successful initial, slab, and refresh requests also provide memory-only freshness coverage for five minutes: scrolling to a visible-plus-buffer range with any stale gap refreshes it immediately, while fully fresh coverage suppresses a duplicate request. Required two-month slab expansion still runs first and remains the only operation that grows the Fetched Window. A complete success atomically applies Google's current additions, edits, moves, declines, and deletions while a failure retains existing events with a warning and retries on connectivity return or the next active interval. An open Event Detail Popover tracks its canonical Calendar Event identity: a successful edit or in-range move updates every presented field in place, deletion, decline, movement outside the refreshed range, or Disconnect on This Device dismisses it, and refresh failure leaves it unchanged. Requests serialize with initial and slab fetching, and their triggers coalesce against current state and the latest visible range. The cadence uses one cancellable sleep rather than a continuously running timer and introduces no background processing. The picker reloads live Source Calendars on every opening with recoverable loading, error, and Retry states, reconciles confirmed additions and removals through reopening, treats a zero-source response as the persisted empty exception, and recovers a selected source's forbidden or not-found event failure with one live reload, reconciliation, and one aggregate retry. The same occurrence returned through multiple Selected Source Calendars presents once — canonical identity is Google's `iCalUID` plus `originalStartTime` (or the occurrence's start), with a source-scoped fallback that never guesses across calendars — using the deterministic winning copy, and Event Detail presents that winning Source Calendar's color and summary. A compact actions menu provides Select All with no product count cap and Reset to Primary with the deterministic fallback; blank summaries present as "Untitled calendar", duplicates take deterministic ordinal suffixes, and rows, the minimum-one explanation, and the count-announcing control carry full VoiceOver, Switch Control, keyboard, Dynamic Type, and right-to-left behavior. There is no search, day list, or offline placeholder. Accepted behavior is recorded in [`docs/specs/calendar-surface.md`](docs/specs/calendar-surface.md) § Calendar Events (release gate).

Behind a TLS-intercepting corporate proxy (for example Netskope), simulator HTTPS to Google fails with `NSURLErrorDomain -1200` until the proxy's root CA is trusted by the simulator, which has its own trust store separate from macOS. Export the proxy's current root from a live connection (`openssl s_client -showcerts -connect oauth2.googleapis.com:443 </dev/null`, last certificate) rather than from the Mac keychain, which may hold an expired earlier generation, and install it with `xcrun simctl keychain booted add-root-cert <cert.pem>`. Repeat per simulator and after erasing one.

## Command-line validation

Every command selects the full Xcode explicitly through `DEVELOPER_DIR`; it does not change the machine-wide `xcode-select` setting.

Build the Release app for Simulator without signing:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/Planner.xcodeproj \
  -scheme Planner \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the Swift Testing suite on the installed iOS 18.5 runtime:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/Planner.xcodeproj \
  -scheme Planner \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

Compile the iOS 17.0 deployment target for a generic device without signing:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project ios/Planner.xcodeproj \
  -scheme Planner \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Swift 6 strict-concurrency checking and warnings-as-errors are project settings, so the same checks apply in Xcode, locally, and in CI. The focused macOS workflow selects Xcode 26.6 through `DEVELOPER_DIR` and delegates to [`scripts/ci.sh`](scripts/ci.sh), which builds the app and runs the suite on one available iPhone Simulator without invoking the web toolchain.

## Supported presentation

- Universal iPhone and iPad app, minimum iOS/iPadOS 17.0
- iPhone portrait and both landscape orientations
- Every iPad orientation, Split View, and Stage Manager
- Full-width Calendar Grid with fixed 96-point Week Rows, event-free in committed configurations and presenting Calendar Events in gate-on development builds
- Gregorian, Monday-first civil dates over the Extended Calendar Range
- System-locale text, numerals, weekend rules, and right-to-left mirroring
- Fixed light appearance, static launch background, and native scrolling

The accepted behavior and manual validation matrix are recorded in [`docs/specs/calendar-surface.md`](docs/specs/calendar-surface.md).

## Deliberate exclusions

This delivery stack has no date selection, general navigation, Source Calendar search, analytics, settings, extensions, background-processing entitlement, or distribution automation in its committed configurations. Scrolling and the Today Jump are the only default-build product interactions. Behind the release gate, the Google Account Connection restores across launches, gates Calendar data behind disclosure version 3, loads and reconciles Source Calendars, exposes the native iOS Source Calendar Picker, fetches resolved-source events directly from Google, presents Calendar Events memory-only, and summons the read-only Event Detail Popover. Only opaque account identifiers and Selected Source Calendar IDs join disclosure and installation markers in app-local persistence; profile data, tokens, Source Calendar presentation data, and Calendar Events remain unstored by Planner.

Custom accessibility descriptions, accessibility-size layout tuning, formal accessibility automation, App Store submission, TestFlight, signing management, archiving, and iOS 17 runtime execution are deliberately deferred.
