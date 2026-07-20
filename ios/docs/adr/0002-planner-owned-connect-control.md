# Planner-owned connect control

## Status

Accepted. Amends the presentation posture of [`0001-use-google-sign-in-for-native-account-connection.md`](0001-use-google-sign-in-for-native-account-connection.md), which remains in force for everything else (the SDK, the OAuth client, scopes, and Keychain persistence are unchanged).

## Context

ADR 0001 adopted Google's supplied SwiftUI sign-in button for the disconnected iOS Account Control, and the connection spec stated that Google owns the button and its localization. In the iOS Calendar Header the supplied button clashed with Planner's warm beige/olive presentation and with the connected control, which is already a Planner-styled capsule; the web version presents a custom "Connect Google" capsule. Google's sign-in branding requirements attach to Google's "G" logo and the "Sign in with Google" phrasing, not to a custom control that uses neither.

## Decision

The disconnected iOS Account Control is a Planner-owned capsule mirroring the connected form: a person-glyph circle in place of the avatar, a "Connect Google" label only when the measured width fits, and an enter-style affordance glyph, with a dimmed non-interactive state while restoration or a connection attempt is in flight. It uses no Google logo and no "Sign in with Google" phrasing. With no code importing it, the SDK's supplied-button module (`GoogleSignInSwift`) and its bundled Roboto brand font are removed from the app's dependency graph; the core `GoogleSignIn` module — authorization callbacks, token refresh, and Keychain persistence — stays.

## Consequences

Planner now owns the connect control's copy, which is English-only like all existing Planner chrome; Google's free button localization is given up until Planner localizes its own strings. VoiceOver leads with the control's visible text, preserving the spec rule that spoken labels match what sighted users see. If Google changes its branding guidance, Planner must review the custom control itself rather than inheriting compliance from the SDK. Reverting to the supplied button would mean restoring the `GoogleSignInSwift` product dependency and accepting Google's rendering in the header again.
