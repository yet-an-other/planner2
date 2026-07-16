# Planner for iOS and iPadOS

This directory is Planner's self-contained native delivery stack. It builds a universal SwiftUI app for iPhone and iPad and shares no executable code or build tooling with [`web/`](../web/).

## Requirements

- macOS with the full Xcode 26.6 application installed at `/Applications/Xcode.app`
- The iOS 18.5 Simulator runtime for the documented test destination
- No package manager, project generator, or third-party dependency

The application deployment target remains iOS/iPadOS 17.0. The locally installed runtimes do not include iOS 17, so execution on an actual iOS 17 runtime remains a required pre-release check.

## Open and run

From the repository root:

```sh
open ios/Planner.xcodeproj
```

Select the shared **Planner** scheme and an iPhone or iPad Simulator. A new process opens Today's Week Row at the top. The app supports iPhone portrait and landscape, all iPad orientations, Split View, and Stage Manager in one non-persistent scene.

Simulator builds and tests do not require a development team. To run on a physical device, choose a personal team in your local Xcode settings; do not commit that team to the project.

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

This delivery stack has no Calendar Events, date selection, navigation, Google Account Connection, Source Calendar, persistence, networking, permissions, analytics, settings, extensions, background-processing entitlement, or distribution automation. Scrolling and the Today Jump are the only product interactions.

Custom accessibility descriptions, accessibility-size layout tuning, formal accessibility automation, App Store submission, TestFlight, signing management, archiving, and iOS 17 runtime execution are deliberately deferred.
