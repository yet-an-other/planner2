# The Planner

A personal planning product.
This self-contained pnpm workspace contains `web-ui` (React + Vite SPA),
`server` (Hono Node API + SPA host), `contracts` (web API transport types), and
`deploy` (GitOps charts and release tooling). Run the commands below from this
`web/` directory.

## Run locally

The app runs **connected only** — the Google Account Connection is the product's
core flow, so there is no zero-setup disconnected mode documented here. Running
it requires a Google Cloud OAuth client (one-time, per contributor).

### Prerequisites

- Node.js (v20+ recommended)
- pnpm (declared `packageManager: pnpm@11.6.0`)

### 1. Install dependencies

```bash
pnpm install
```

### 2. Create a Google OAuth client (once)

The backend performs the Google authorization-code flow server-side, so you need
your own OAuth "Web application" client — the `GOOGLE_CLIENT_SECRET` must never
be shared or committed (ADR 0005).

1. In the [Google Cloud Console](https://console.cloud.google.com/), create or
   pick a project.
2. **APIs & Services → Library →** enable the **Google Calendar API**.
3. **APIs & Services → OAuth consent screen:**
   - User type: **External**.
   - Add yourself as a **Test User** (the app stays in "Testing" status; no
     verification needed for local dev).
   - Scopes are requested by the app at runtime (`openid email profile
   https://www.googleapis.com/auth/calendar.readonly`) — do **not** configure
   scopes in the Console.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID:**
   - Application type: **Web application**.
   - **Authorized JavaScript origins:** `http://localhost:3000`
   - **Do not add any redirect URIs.** The SPA uses the Google Identity Services
     *code client* with `redirect_uri: 'postmessage'`, which is implicit — no
     redirect URI is registered in the Console. Adding one (e.g.
     `http://localhost:3000/callback`) is wrong for this flow and produces a
     `redirect_uri_mismatch` error at connect time.
5. Copy the **Client ID** and **Client Secret**.

### 3. Configure runtime environment

The local file is gitignored (`.gitignore` keeps `.env.example` only). Copy the
server example and fill in your values.

```bash
cp server/.env.example server/.env.local
```

**`server/.env.local`**:

```
VITE_GOOGLE_CLIENT_ID=<your-client-id>.apps.googleusercontent.com
GOOGLE_CLIENT_ID=<your-client-id>.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=<your-client-secret>
SESSION_COOKIE_KEY=<64 hex chars>
APP_VERSION=dev
```

Notes:
- `VITE_GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_ID` must be the **same value**. The
  server validates them at startup and serves the public id to the browser from
  `/runtime-config.js`; Vite does not embed environment-specific OAuth values.
- Generate `SESSION_COOKIE_KEY` **once** and reuse it across restarts:
  ```bash
  node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
  ```
  A fresh key on every boot invalidates every existing session cookie, so the
  ~30-day persistent connection (ADR 0005) would never survive a server restart
  locally.

### 4. Run the dev loop (two terminals)

The app is **single-origin**: the Hono server serves the API at `/api/*` **and**
the built SPA at `/` on one port (`http://localhost:3000`), so the session
cookie is strictly first-party (ADR 0005). There is no split-origin Vite dev
server for the connected flow.

**Terminal 1 — server** (API + SPA host, hot-reloads on server changes):
```bash
pnpm --filter @planner/web-server dev
```

**Terminal 2 — web UI** (rebuilds `web-ui/dist` incrementally on frontend
changes; the server serves the fresh files on the next request — no server
restart needed, just refresh the browser):
```bash
pnpm --filter @planner/web-ui dev:build
```

> The web UI `dev:build` script runs `vite build --watch` (no `tsc -b` — type
> errors are surfaced by your editor and by `pnpm typecheck` / CI, not in the
> watch loop).

### 5. Open the app

Open **`http://localhost:3000`** — not `127.0.0.1`, and not `https://`.

The session cookie is set with the `Secure` flag (see `server/src/session-cookie.ts`).
Browsers accept `Secure` cookies over plain HTTP **only** for the literal host
`localhost`; `127.0.0.1` and LAN IPs silently drop the cookie, so the Google
Account Connection would appear to never persist (connect succeeds, but the next
request returns 401 with no visible error). Use `http://localhost:3000`.

The server also prints the URL at boot: `planner server listening on
http://localhost:3000`.

### Connection behavior

The Google Account Connection is local to one browser profile. **Disconnect
on This Device** issues `DELETE /api/connection`, which clears only the
profile's encrypted session cookie without contacting Google — it never
revokes the project-wide Google Authorization Grant, so iOS and other
browser profiles stay connected. Each browser tab owns its connection state
independently: there is no cross-tab synchronization, and a sibling tab
keeps working from its own in-memory access token until it reloads or its
own token refresh discovers the cleared cookie. See
[`docs/specs/calendar-surface.md`](docs/specs/calendar-surface.md) and ADR
[`0005`](docs/adr/0005-persistent-google-account-connection-via-minimal-backend.md)
with system ADR `0002-keep-google-account-connections-local`.

## Deployment

GitOps bootstrap, secret rotation, image publication, staging advancement,
production promotion, and rollback are documented in [`deploy/README.md`](deploy/README.md).

## Other scripts

From the `web/` workspace root:

- `pnpm test` — run tests across all workspaces (vitest)
- `pnpm typecheck` — typecheck all workspaces

## Troubleshooting

- **Connect succeeds but the connection doesn't persist (next page load is
  disconnected, no error).** You're almost certainly opening the app via
  `127.0.0.1` or `https://`. Use `http://localhost:3000` exactly — see step 5.
- **`redirect_uri_mismatch` at connect.** You added a redirect URI in the Cloud
  Console. Remove it — the app uses `postmessage`, which needs no registered
  redirect URI. See step 2.
- **`Missing required environment variable` at server startup.** The server's
  `dev` script loads `server/.env.local` via `tsx --env-file`; create it from
  `server/.env.example` and provide every required value (step 3).
- **`VITE_GOOGLE_CLIENT_ID must match GOOGLE_CLIENT_ID`.** Use the same Google
  OAuth Web client id for the browser and server entries in `server/.env.local`.
- **`SESSION_COOKIE_KEY must be 32 bytes (64 hex chars)`.** Regenerate it with
  the `node -e "..."` command in step 3.
- **Connection resets on every server restart.** You're regenerating
  `SESSION_COOKIE_KEY` on each boot. Generate it once, store it in
  `server/.env.local`, and reuse it.
