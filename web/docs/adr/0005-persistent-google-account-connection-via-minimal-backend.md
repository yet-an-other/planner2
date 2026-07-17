# Persistent Google Account Connection via a minimal backend

## Status

Accepted. Supersedes the "no backend" stance recorded in ADR 0003. The revoke-on-logout behavior is superseded by system ADR [`0002-keep-google-account-connections-local`](../../../docs/adr/0002-keep-google-account-connections-local.md).

## Context

The Planner was a backend-less browser SPA (ADR 0003). Its Google Account
Connection used Google Identity Services' token client with `prompt: 'consent'`,
keeping only a short-lived access token (1 hour) in React state — so every page
reload disconnected the user and every connect re-showed the consent screen. The
product needs the connection to persist for about a month, or until explicit
disconnect, without re-consent.

That is impossible client-side: GIS access tokens expire in 1 hour, the
token-client flow issues no refresh token, and only the authorization-code flow
yields a refresh token — which requires a `client_secret` that must never live in
browser code.

## Decision

Introduce a minimal, stateless backend of three same-origin endpoints under
`/api/*` that performs the Google authorization-code flow, holds the resulting
refresh token in an encrypted `HttpOnly; Secure; SameSite=Lax` session cookie,
and serves the SPA fresh short-lived access tokens on demand.

The backend is a single Node.js + TypeScript server (Hono), hosted in the
project's self-hosted k8s cluster, that serves the built SPA at `/` and the API
at `/api/*` on one origin — making the session cookie strictly first-party by
construction. Node + TypeScript is chosen to share one toolchain and types with
the SPA; the deep token-exchange/refresh/encrypt/revoke logic is kept as a
runtime-agnostic core so the runtime can change without rewriting it.

- **Connect** — the SPA uses the GIS *code client* (popup) to obtain a one-time
  authorization code and POSTs it to `/api/auth/callback`, which exchanges it
  (server-side `client_secret`) for access + refresh tokens, decodes the profile
  from the `id_token`, and encrypts everything into the session cookie.
- **Token** — `/api/token` decrypts the cookie, returns the cached access token
  if still valid, otherwise refreshes via Google and re-encrypts/re-sets the
  cookie. The SPA calls this on load and retries once on any `401`.
- **Logout** — `/api/logout` revokes the refresh token at Google and clears the
  cookie.

The SPA keeps calling the Google Calendar API directly (the existing
fetch/normalization layer is unchanged); the backend never proxies calendar
data. Sessions slide: each refresh re-sets the cookie's 30-day `Max-Age`, so the
connection survives until explicit disconnect or ~30 days of inactivity.

## Consequences

- **Reverses "no backend" (ADR 0003).** Hosting now requires a stateless Node.js
  server, plus a `GOOGLE_CLIENT_SECRET`, a `GOOGLE_CLIENT_ID`, and a
  cookie-encryption key provided as env vars backed by k8s Secrets. The
  encryption key is shared across replicas; because sessions are stateless and
  encrypted in the cookie, no session affinity or database is needed.
- **Refresh tokens never reach the browser.** The cookie is `HttpOnly`; the only
  credential exposed to the page is the 1-hour access token — same exposure as
  today, but now refreshable without a popup.
- **Per-device sessions.** Each browser gets its own cookie + refresh token, with
  no cross-device session list and no "logout everywhere" without a future store.
- **Refresh failure is non-fatal.** If Google revokes the grant, `/api/token`
  returns disconnected and the Calendar Surface falls back to Saved Busy Blocks
  (ADR 0001), prompting a normal reconnect.
- **Encryption:** AES-256-GCM with a random per-token nonce; the 256-bit key
  lives in a server env var. Key rotation (keyring) is deferred.

## Considered options

- **Client-only silent re-consent via GIS token client.** Rejected: no refresh
  token, popup/gesture-bound renewal, no deterministic month-long session.
- **Backend that proxies all Google Calendar calls.** Rejected: ~doubles the
  backend and rewrites a thick, tested fetch/normalization layer for a marginal
  access-token-privacy gain.
- **Stateful store (DB/KV) for refresh tokens.** Rejected for v1: adds infra for
  "logout everywhere"/reuse-detection the product doesn't need.
- **Managed auth (Supabase/Firebase Auth).** Rejected: doesn't cleanly manage
  Google Calendar-scope token refresh and adds platform lock-in for three
  endpoints' worth of work.
- **Cross-origin API.** Rejected: same-origin avoids CORS, preflight,
  `SameSite=None`, and third-party-cookie/ITP fragility at no operational cost.
- **Serverless functions (Vercel/Cloudflare).** Rejected: the product is
  self-hosted in a k8s cluster, not on a serverless platform; a single stateless
  Node server serves the SPA and API on one origin.
