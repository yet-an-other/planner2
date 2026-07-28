# iOS Google Account Connection specification

- **Status:** Accepted
- **Applies to:** Planner native iOS/iPadOS Google Account Connection
- **Minimum deployment target:** iOS/iPadOS 17.0
- **Related:** [`calendar-surface.md`](calendar-surface.md), [`source-calendar-selection.md`](source-calendar-selection.md), [`../adr/0001-use-google-sign-in-for-native-account-connection.md`](../adr/0001-use-google-sign-in-for-native-account-connection.md), [`../adr/0002-planner-owned-connect-control.md`](../adr/0002-planner-owned-connect-control.md), [`../adr/0006-persist-selected-source-calendars-per-account.md`](../adr/0006-persist-selected-source-calendars-per-account.md), system ADR [`0002-keep-google-account-connections-local.md`](../../../docs/adr/0002-keep-google-account-connections-local.md), [`../research/google-account-connection-authentication.md`](../research/google-account-connection-authentication.md)

## Purpose and ownership

The **iOS Google Account Connection** authorizes Planner for future read-only Google Calendar features from the native app. It presents through the **iOS Account Control** and **iOS Header Status** in the **iOS Calendar Header**, establishes Google identity plus the `calendar.readonly` scope through the official Google Sign-In SDK, and stays strictly local to one installation on one physical device. This slice performs no Google Calendar API request and fetches no Calendar data.

Planning owns the shared **Google Authorization Grant**, **Google Account Connection**, and **Disconnect on This Device** language. The iOS Experience owns the **iOS Account Control** and **iOS Header Status** presentation, including the connect control's English-only copy. Google owns its authorization UI.

## Accepted behavior

### Release gate and configuration

- A build-time release gate controls the entire addition. While off — every committed and production configuration — the app initializes no connection behavior, mounts neither the iOS Account Control nor the iOS Header Status, and renders the accepted 80-point iOS Calendar Header.
- The gate remains off for production until the external release inputs below are complete. Calendar Events and the disclosure-gated Source Calendar restoration path have landed behind it. Disclosure version 4 states the Stored Calendar Events persistence behavior specified in [`calendar-surface.md`](calendar-surface.md) (ADR 0007).
- With the gate on, the iOS OAuth client ID, reversed callback scheme, and HTTPS Privacy Policy URL arrive as environment-specific build settings substituted into the app bundle. No client secret setting exists anywhere.
- A gate-on build with missing or invalid values leaves the iOS Calendar Surface usable, disables Connect through the control's dimmed, non-interactive state, and reports "Google connection is not configured".
- Ordinary builds, previews, tests, and CI require no Google credentials, account, callback, or network access.

### Header composition

- With the gate on, the fixed iOS Calendar Header presents a 44-point title/control row, a fixed 14-point iOS Header Status row, and the 36-point weekday row. The Product Name stays leading, the Visible Month stays geometrically centered and remains the Today Jump, and the iOS Account Control stays trailing.
- The iOS Header Status always reserves its height so messages never move the Calendar Grid. It uses the full width between the 16-point margins, aligns trailing (mirroring naturally), stays on one visual line with tail truncation, exposes the complete message to VoiceOver, and announces changes as a polite live region. Informational, recoverable-warning, and error tones come from the palette; the message copy carries meaning without color. The latest message remains until superseded; a first launch with no saved connection leaves the row blank.
- Account transitions never change calendar scroll identity, the topmost Week Row, or Today Jump behavior.

### iOS Account Control presentation

- The disconnected presentation is a Planner-styled capsule mirroring the connected form: a person-glyph circle, a "Connect Google" label only when the measured width fits, and an enter-style affordance glyph distinct from the connected form's disconnect glyph. The capsule uses no Google logo and no "Sign in with Google" phrasing; its copy is English-only. Every form provides at least a 44-point activation target.
- The connected presentation is a Planner-styled capsule with the account avatar — profile image once loaded, initials underneath at all times so a broken image never appears, a neutral person glyph without a display name — the Disconnect on This Device affordance, and the display name only when the measured width fits. Compact-versus-labeled selection always uses actual available width, never device category.
- Restoration and Connect in flight present the same capsule dimmed and non-interactive; every control state preserves focus, pointer, hover, RTL, and accessibility behavior. VoiceOver labels lead with the visible button text when disconnected ("Connect Google") and announce the connected account identity with the local disconnect action when connected.
- Every form carries the connection dot: a badge floating eight points past the capsule's top-trailing corner that presents the Google Account Connection state at a glance — green when connected, gray when disconnected, pulsing gray while restoring or connecting. Connection warnings and errors never change the dot; the iOS Header Status text carries them. The dot adds no width to the trailing control cluster, mirrors naturally for right-to-left, and is folded into the control's own accessibility rather than exposed as a separate element.

### Connect

- The first Connect for disclosure version 4 presents a compact native explanation before any Google authorization UI: Planner reads events from the Selected Source Calendars, stores their IDs on this device, stores Calendar Events on this device only — excluded from backups and removed on Disconnect on This Device — and cannot modify Google Calendar. Continue, Cancel, and Privacy Policy actions remain; the Privacy Policy action opens the configured HTTPS URL.
- Continue acknowledges the disclosure version through an install-local, non-identifying marker and resumes the same Connect flow; acknowledging suppresses the sheet until the version increments. Cancel or interactive dismissal opens no Google UI and reports "Google connection cancelled".
- A restored connection whose installation acknowledged an older version presents the version 4 explanation before any Source Calendar request, Calendar Event request, Stored Calendar Events write, or selection write. Cancellation preserves the Google Account Connection in an event-empty suspended state, keeps Disconnect on This Device available, reports review guidance, and re-presents the explanation on the next foreground entry.
- One authorization request obtains `openid`, `email`, `profile`, and `https://www.googleapis.com/auth/calendar.readonly` through the configured iOS OAuth client, so existing project-wide consent is reused without a redundant prompt. The reversed-client-ID callback route returns through the app's URL handling to the SDK.
- Connected state is published only when the Calendar scope is present. Identity without it clears the partial local sign-in, remains disconnected, and reports "Calendar read access is required".
- User cancellation remains disconnected and reports "Google connection cancelled". Other failures map to stable Planner-owned copy: "Google connection failed. Try again". Raw Google errors never reach the iOS Header Status.
- Exactly one connected account exists at a time; connecting another requires Disconnect on This Device first. Duplicate activations never launch a second authorization.

### Restoration and recovery

- Startup enters a restoring presentation with the control disabled and "Restoring Google account…" in the status row instead of flashing a false Connect.
- A valid saved connection with the required scope restores connected identity; the resting connected state publishes no status message — the connection dot carries it — and the status row settles blank. Google Sign-In refreshes expired access credentials when refresh is available. No saved Google Account Connection becomes an ordinary blank disconnected state. Planner imposes no arbitrary connection expiry.
- Confirmed invalid or revoked authorization clears the local connection and reports "Google connection expired. Connect again".
- A transient connectivity failure preserves the connected state and reports "You're offline. Google connection will be checked when online". Validation retries when connectivity returns and when the app next becomes active, event-driven with no polling, timers, or background processing. Recovery success clears the warning and the status row settles blank without user action. Only confirmed invalidation transitions to disconnected.
- Stale asynchronous completions never overwrite newer user intent.

### Disconnect on This Device

- One activation of the connected control immediately Disconnects on This Device without confirmation or connectivity, through the SDK's local sign-out only. No confirmation text follows: the control's transformation and the gray connection dot are the feedback.
- Disconnect never invokes SDK disconnect or Google revocation: the project-wide Google Authorization Grant and every other Planner connection — web, other iOS devices, other browser profiles — remain intact.

### Installation boundary

- A Google Account Connection belongs to one installation on one physical device. An install-local marker (deleted by uninstall, carried by backups) correlated with a non-migrating Keychain device marker distinguishes an ordinary relaunch or app update from a fresh installation or a backup restored to different hardware.
- Fresh-install or migrated-device detection clears stale Google Sign-In state through local sign-out before restoration and starts disconnected. Marker state is non-identifying, and partial or corrupted state fails safe into the clearing path.

### Data minimization

- Google Sign-In owns Google credential persistence and refresh in its Keychain storage. Planner persists no access tokens, refresh tokens, email, display name, profile image URL, or Source Calendar presentation data. ADR 0006 permits stable opaque account identifiers associated with stored per-account selections and their Selected Source Calendar IDs in app-local preferences. ADR 0007 permits per-account Stored Calendar Events in backup-excluded Application Support storage, wiped by Disconnect on This Device. Other presentation state is memory-only; the profile image loads through an ephemeral `URLSession`. Planner logs no tokens, OAuth codes, profile identifiers, Calendar IDs, or raw SDK responses.

## Interaction and product exclusions

This slice contains no:

- Google Calendar API request, Source Calendar, Calendar Event, or any other Calendar resource fetch
- Persistence of account profile fields, Google tokens, or Source Calendar presentation data beyond the SDK-owned credentials, non-identifying disclosure and installation markers, the narrow Selected Source Calendar ID exception in ADR 0006, and the Stored Calendar Events boundary in ADR 0007
- Account switcher or more than one connected account
- Project-wide Revoke Planner Access action, Google Account Connection list, or remote device management
- Native Planner backend connection, web-cookie protocol reuse, or embedded client secret
- Sign in with Apple or any required onboarding or account gate before the iOS Calendar Surface
- Analytics, account telemetry, crash-reporting payloads, or logging of user identity
- Background refresh, push notifications, widgets, extensions, or continuously running timers
- Cross-Account Protection integration

## Deterministic verification

Swift Testing drives the Google Account Connection module through a fake Google Sign-In adapter, an in-memory disclosure store, a fake connectivity monitor, and deterministic installation markers. Coverage includes:

- Release-gate and configuration validation, including that the committed app bundle stays gated off
- Restoration: valid, refreshed, no saved connection, missing scope, invalid authorization, stale completion
- Connect: success, existing-consent reuse, missing Calendar scope, cancellation, generic and connectivity failure, duplicate activation protection, connect-while-restoring and connect-while-connected refusal
- Disclosure explanation: first-Connect presentation and resumption, restored-account version 3 suspension, cancellation with connection retention, foreground re-presentation, suppression, version re-increment, and duplicate protection
- Offline and recovery: preservation with warning, connectivity-return retry, repeated transitions, invalidation from the warning state, silent generic failure, offline disconnect, disconnect race, idle return, module lifetime end
- Installation boundary: first install, relaunch, update-equivalent state, reinstall, migrated backup, mismatch, corruption, and module clearing integration
- Disconnect on This Device: immediate local sign-out and guards
- Connection dot appearance: the pure mapping from control presentation to green, gray, and pulsing-gray forms, with connection warnings and errors unable to reach it

Deterministic SwiftUI previews cover gate-off, unconfigured, restoring, connecting, explanation, disconnected, connected (compact, wide, long-name, no-name), offline, cancelled, failed, and expired presentations across compact, wide, long-month, RTL, landscape, and large-text layouts. The Calendar Grid model suite remains unchanged and passing.

## Manual acceptance matrix

Results recorded honestly. Cases requiring production-like OAuth configuration in a real Google Cloud project remain **pending**; no such configuration exists in the repository.

| Scenario | Environment | Result |
| --- | --- | --- |
| Gate-off build keeps the 80-point header | iPhone/iPad simulator, committed configuration | Pass: no control, no status row, unchanged surface |
| Unconfigured gate-on build | iPhone simulator, gate on without values | Pass: disabled control, "Google connection is not configured", surface usable |
| Disconnected/restoring/connected/offline presentations | iPhone/iPad simulator, deterministic module presentations | Pass: adaptive compact/labeled capsule forms, connection dot state presentation, RTL mirroring, centered month preserved |
| Custom connect control | iPhone SE (3rd generation) and 11-inch iPad Pro, iOS 18.5 Simulators | Pass: compact capsule at compact width, labeled "Connect Google" capsule at wide width, no Google button assets; the dimmed non-interactive in-flight state is covered by the deterministic previews |
| Long-name compact fallback | iPhone/iPad simulator | Pass: compact capsule without name at both widths |
| First Connect with disclosure | Production-like iOS OAuth client and consent screen | Pending — external OAuth configuration required |
| Connect success and scope grant | Production-like OAuth configuration | Pending — external OAuth configuration required |
| Existing web grant reuse without redundant prompt | Shared Cloud project with prior web consent | Pending — external OAuth configuration required |
| User cancellation | Production-like OAuth configuration | Pending — external OAuth configuration required |
| Calendar scope denial | Production-like OAuth configuration | Pending — external OAuth configuration required |
| Workspace/admin denial | Managed Google account where practical | Pending — external OAuth configuration required |
| Restoration after termination and device restart | Real signed-in account on device | Pending — external OAuth configuration required |
| Transient offline and automatic recovery | Device connectivity toggling | Pending — external OAuth configuration required |
| Disconnect on This Device while web stays connected | iOS and web in one Cloud project | Pending — external OAuth configuration required |
| Web Disconnect on This Device while iOS stays connected | iOS and web in one Cloud project | Pending — external OAuth configuration required |
| Two iOS devices isolation | Two signed-in devices | Pending — external OAuth configuration required |
| Browser profiles and tabs isolation | Web experience | Pending — see web acceptance |
| Global Google revocation discovery | Google Account permissions removal | Pending — external OAuth configuration required |
| Uninstall/reinstall starts disconnected | Device lifecycle | Pending — external OAuth configuration required |
| Backup migration to another device | Device-to-device restore where practical | Pending — external OAuth configuration required |
| Compact iPhone, iPad Split View/Stage Manager, landscape, RTL, Dynamic Type | Simulators and devices | Partial pass via deterministic previews and simulator screenshots; runtime multitasking pass pending |
| Keyboard focus, pointer hover, VoiceOver labels and announcements | iPad with keyboard/pointer, VoiceOver | Pending — manual accessibility pass |
| Calendar browsing position through account transitions | Simulator | Pass: header heights fixed; top Week Row and Today Jump preserved by existing suite |

## External release inputs

These gates are deliberately **not complete** and are not reported as such:

- An iOS OAuth client bound to Planner's bundle identifier in the shared Google Cloud project, with its reversed callback scheme.
- Google Calendar API enabled and the OAuth consent screen production-ready with the sensitive `calendar.readonly` scope verified as Google requires.
- A public HTTPS Privacy Policy URL whose content covers current and intended Calendar-data handling.
- App Privacy answers covering Planner's and the SDK's account and Calendar data behavior, including the account-linked Selected Source Calendar configuration in ADR 0006 and the Stored Calendar Events boundary in ADR 0007.
- A first user-visible Calendar-data consumer, which alone justifies enabling the production release gate. Delivered behind the gate: Calendar Events on the iOS Calendar Surface. The production flip itself remains open.

## Compliance validation

- **Pinned SDK graph.** Google Sign-In for iOS 9.2.0 is pinned at an exact version with the full dependency graph in `Package.resolved` (AppAuth 2.1.0, GTMAppAuth 5.0.0, gtm-session-fetcher 3.5.0, app-check 11.3.1, GoogleUtilities 8.1.2, Promises 2.4.1, interop 101.0.0); release notes and behavior were reviewed at adoption.
- **Privacy manifest.** Verified in an unsigned Release archive (2026-07-18): the app bundle embeds `PrivacyInfo.xcprivacy` for GoogleSignIn, AppAuth, AppAuthCore, GTMAppAuth, GTMSessionFetcherCore, GoogleUtilities (Environment, Logger, UserDefaults), and Promises — every Apple-listed SDK in the pinned graph. (The 2026-07-18 archive also embedded GoogleSignInSwift's manifest; the supplied-button module and its Roboto brand font were removed from the link when the connect control became Planner-owned, and the manifest list here reflects the current graph.) The archive contains no `Frameworks` directory: all packages are statically linked from source via Swift Package Manager, so Apple's SDK signature requirement (which covers listed binary SDKs) does not apply. Reconfirm the archive contents and Apple's current list before any App Store submission.
- **Fresh-install cleanup.** Google Sign-In 9.2.0 removes its own stale Keychain entries on fresh installs; Planner's installation boundary adds the device-migration case and never deletes SDK Keychain items directly.

## Deferred validation and release work

Real-OAuth acceptance per the matrix above, Google OAuth verification administration, App Store submission, TestFlight distribution, signing administration, and release rollout remain outside implementation. Calendar Events and Source Calendar restoration have landed behind the gate, and disclosure version 4 gates Stored Calendar Events persistence. The user-facing Source Calendar Picker remains a later implementation slice; the production flip remains coupled to the external release inputs above.
