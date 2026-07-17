# Use Google Sign-In for the native account connection

## Status

Accepted.

## Context

The iOS Experience needs a durable Google Account Connection without putting a client secret in the app. Planner's existing web backend is coupled to a browser-only Google Identity Services popup and first-party cookie session; adapting it for a native client would require a separate app-session protocol. Implementing Google's native authorization-code flow directly would make Planner responsible for PKCE, callback validation, token refresh, secure token persistence, and revocation.

## Decision

Use Google's official `GoogleSignIn-iOS` Swift package with a distinct iOS OAuth client in the same Google Cloud project as Planner's web client. Request `openid`, `email`, `profile`, and `https://www.googleapis.com/auth/calendar.readonly`, and let the SDK own authorization callbacks, token refresh, and credential persistence in the Keychain. The iOS app connects directly to Google and does not use Planner's web authentication backend. No Google client secret is embedded in the app. Disconnect on This Device uses the SDK's local `signOut()` operation and never invokes project-wide token revocation, as required by system ADR [`0002-keep-google-account-connections-local`](../../../docs/adr/0002-keep-google-account-connections-local.md).

## Consequences

This supersedes the iOS delivery stack's previous exclusion of third-party packages. The app must configure an iOS OAuth client and callback URL scheme, pin and audit the SDK, verify its privacy manifest in release archives, and maintain accurate App Privacy disclosures. The web authentication architecture remains unchanged; a backend-mediated native connection can be reconsidered if Planner later needs server-side Calendar access.

See [`../research/google-account-connection-authentication.md`](../research/google-account-connection-authentication.md) for the supporting primary-source research.
