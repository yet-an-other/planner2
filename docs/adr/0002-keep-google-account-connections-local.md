# Keep Google Account Connections local to each client

## Status

Accepted. This supersedes the revoke-on-logout portion of Web Experience ADR [`0005-persistent-google-account-connection-via-minimal-backend`](../../web/docs/adr/0005-persistent-google-account-connection-via-minimal-backend.md).

## Context

Google token revocation removes the authorization grant for every OAuth client in the same Google Cloud project, so revoking from one Planner client can disconnect web and iOS sessions on other devices. Users expect Disconnect on This Device in one app installation or browser profile to leave their other Planner connections intact.

## Decision

A Google Account Connection is local to one app installation or browser profile. Disconnect on This Device removes that client's locally retained credentials or session but does not revoke the project-wide Google Authorization Grant. The iOS Experience uses Google Sign-In's local `signOut()` operation. The Web Experience deletes its connection through `DELETE /api/connection`, which clears only its encrypted session cookie. Each browser tab owns its connection state independently; there is no cross-tab broadcast or synchronization mechanism, so a sibling tab keeps working from its own in-memory access token until it reloads or its own `/api/token` refresh discovers the cleared cookie. Neither experience calls Google's token-revocation endpoint during Disconnect on This Device.

## Consequences

Disconnect on This Device works offline in iOS and cannot terminate another Planner connection. Google may retain Planner's authorization grant after the last local connection is removed; users who want global revocation must use their Google Account permissions unless Planner later adds an explicitly global revoke action. The web backend may continue using its refresh token while its browser session exists, but it must discard that token when clearing the cookie rather than revoke it. Because only the backend can clear the Web Experience's `HttpOnly` cookie, a failed web disconnect request leaves that connection intact and reports an error. Because tabs are independent, a browser profile with multiple open tabs can briefly show inconsistent connection state across tabs after a Connect or Disconnect on This Device in one of them; this is an accepted simplification, not a defect, and immediate cross-tab convergence may be reconsidered later as an explicit, separately designed feature.
