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

The iOS Account Control and iOS Header Status sit behind a build-time release gate that stays **off** in every committed configuration: the app then initializes no connection behavior and the iOS Calendar Header keeps its accepted 100-point form. The gate remains off for production until a Calendar-data feature provides visible value for the sensitive scope.

To enable the connection in a development build, copy [`Configurations/GoogleConnection.local.xcconfig.example`](Configurations/GoogleConnection.local.xcconfig.example) to `Configurations/GoogleConnection.local.xcconfig` (git-ignored) and supply the environment-specific inputs: the iOS OAuth client ID, its reversed form (the OAuth callback URL scheme), and the public HTTPS Privacy Policy URL. With the gate on, missing or invalid values leave the iOS Calendar Surface usable, disable Connect, and report “Google connection is not configured” in the iOS Header Status. Planner accepts no Google client secret: an installed app cannot keep one, so no such setting exists.

A configured development build restores a saved connection silently at launch — entering a restoring presentation instead of flashing a false Connect, refreshing expired credentials through Google Sign-In, and clearing confirmed-invalid authorization with reconnect guidance — and runs one Connect flow for Google identity and read-only Calendar access through the official Google Sign-In SDK. The first Connect in an installation opens a compact native explanation of the read-only access (stating that this build downloads no Calendar data) with Continue, Cancel, and Privacy Policy actions; acknowledging it suppresses the sheet until the disclosure version increments. A connected session survives offline periods with a recoverable warning and revalidates when connectivity returns or the app becomes active; only confirmed invalidation disconnects. An installation boundary correlates an install-local marker with a non-migrating Keychain device marker, so a reinstall or a backup restored to new hardware clears stale sign-in state locally and starts disconnected, while ordinary relaunches, updates, and device restarts keep a valid connection. The compact connected control disconnects on this device through local SDK sign-out only — never SDK disconnect or Google revocation, so sibling Planner connections stay intact. Planner persists no tokens or account profile data itself; Google Sign-In owns credential storage.

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
- Full-width, event-free Calendar Grid with fixed 96-point Week Rows
- Gregorian, Monday-first civil dates over the Extended Calendar Range
- System-locale text, numerals, weekend rules, and right-to-left mirroring
- Fixed light appearance, static launch background, and native scrolling

The accepted behavior and manual validation matrix are recorded in [`docs/specs/calendar-surface.md`](docs/specs/calendar-surface.md).

## Deliberate exclusions

This delivery stack has no Calendar Events, date selection, navigation, Source Calendar, persistence, networking, permissions, analytics, settings, extensions, background-processing entitlement, or distribution automation. Scrolling and the Today Jump are the only product interactions. Behind the release gate, the Google Account Connection restores across launches, explains its read-only access before the first Connect, connects, recovers from offline periods, stays bound to one installation and device, and disconnects on this device. This slice makes no Google Calendar API request and persists no Calendar or account profile data, and the release gate keeps the addition inactive in default builds.

Custom accessibility descriptions, accessibility-size layout tuning, formal accessibility automation, App Store submission, TestFlight, signing management, archiving, and iOS 17 runtime execution are deliberately deferred.
