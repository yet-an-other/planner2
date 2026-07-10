# The Planner

A personal planning product whose first slice is a calendar-only surface.
pnpm monorepo: `web` (React + Vite SPA), `server` (Hono Node API + SPA host),
`shared` (types shared across both).

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

### 3. Configure environment files

Both files are gitignored (`.gitignore` keeps `.env.example` only). Copy the
examples and fill in your values.

```bash
cp web/.env.example     web/.env.local
cp server/.env.example  server/.env.local
```

**`web/.env.local`** — one var:

```
VITE_GOOGLE_CLIENT_ID=<your-client-id>.apps.googleusercontent.com
```

**`server/.env.local`** — three vars:

```
GOOGLE_CLIENT_ID=<your-client-id>.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=<your-client-secret>
SESSION_COOKIE_KEY=<64 hex chars>
```

Notes:
- `VITE_GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_ID` are the **same value** — the one
  OAuth client id. The `VITE_` prefix only controls whether Vite inlines it into
  the browser bundle; both reference the single client.
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
pnpm --filter @planner/server dev
```

**Terminal 2 — web** (rebuilds `web/dist` incrementally on frontend changes;
the server serves the fresh files on the next request — no server restart
needed, just refresh the browser):
```bash
pnpm --filter planner dev:build
```

> The web `dev:build` script runs `vite build --watch` (no `tsc -b` — type
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

## Other scripts

From the repo root:

- `pnpm test` — run tests across all workspaces (vitest)
- `pnpm typecheck` — typecheck all workspaces

## Troubleshooting

- **Connect succeeds but the connection doesn't persist (next page load is
  disconnected, no error).** You're almost certainly opening the app via
  `127.0.0.1` or `https://`. Use `http://localhost:3000` exactly — see step 5.
- **`redirect_uri_mismatch` at connect.** You added a redirect URI in the Cloud
  Console. Remove it — the app uses `postmessage`, which needs no registered
  redirect URI. See step 2.
- **`Missing required environment variable: GOOGLE_CLIENT_ID` (or
  `GOOGLE_CLIENT_SECRET` / `SESSION_COOKIE_KEY`).** The server's `dev` script
  loads `server/.env.local` via `tsx --env-file`; create it from
  `server/.env.example` (step 3).
- **`SESSION_COOKIE_KEY must be 32 bytes (64 hex chars)`.** Regenerate it with
  the `node -e "..."` command in step 3.
- **Connection resets on every server restart.** You're regenerating
  `SESSION_COOKIE_KEY` on each boot. Generate it once, store it in
  `server/.env.local`, and reuse it.
