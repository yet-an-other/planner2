# Planner GitOps operations

Planner uses Argo CD for ongoing workload reconciliation. The local bootstrap
command creates the cluster-local boundary that cannot live in Git: the Planner
namespace, runtime Secret, restricted AppProject, and Application. It does not
perform subsequent workload upgrades directly.

## Environments

| Target | Purpose | Public origin | Kubeconfig | Runtime input |
| --- | --- | --- | --- | --- |
| `proxmox` | staging | `https://planner.bdgn.me` | `~/remote-kube/proxmox/config` | `.env.proxmox` in this directory |
| `hetzner` | production | `https://planner.ivan-b.com` | `~/remote-kube/hetzner/config` | `.env.hetzner` in this directory |

The runtime inputs are ignored by Git. Never commit them. Each file contains
exactly these four entries:

```text
VITE_GOOGLE_CLIENT_ID=<environment Google OAuth Web client id>
GOOGLE_CLIENT_ID=<the same environment Google OAuth Web client id>
GOOGLE_CLIENT_SECRET=<environment Google OAuth client secret>
SESSION_COOKIE_KEY=<64 hexadecimal characters>
```

Comments and blank lines are accepted, and values may contain `=`. Unknown,
duplicate, empty, or malformed entries fail validation. The two client ids must
match. Staging and production may use different OAuth clients and may reuse a
cookie key; separation is not enforced. File permissions are the operator's
responsibility and are not a hard bootstrap gate.

Configure each Google OAuth Web client with its environment's HTTPS URL as an
Authorized JavaScript origin. Planner uses the Google Identity Services
`postmessage` flow, so no redirect URI is added.

## Prerequisites

Install `node`, `kubectl`, `helm`, and provide the target kubeconfig. The target
cluster must already have:

- Argo CD and its Application/AppProject CRDs, in namespace `argocd`
- Traefik and the `traefik.io/v1alpha1` IngressRoute CRD
- cert-manager and its Certificate CRD
- a Ready ClusterIssuer named `letsencrypt-dns`
- working public DNS for the environment hostname

Bootstrap always uses normal kubeconfig certificate verification. It has no
insecure TLS mode. An expired API certificate or invalid kubeconfig must be
repaired rather than bypassed. In particular, Hetzner bootstrap remains blocked
until its currently expired Kubernetes API certificate is repaired.

The chart assumes no previous Planner installation and includes no migration or
resource-adoption behavior.

## Bootstrap

The checked-in `sha-0000000` image value is a render-only sentinel. Bootstrap
rejects it before contacting mutating APIs. Publish staging or complete a
protected production promotion so the target values contain a real immutable
image before bootstrapping that environment.

Validate and install staging:

```bash
./deploy/bootstrap.sh proxmox
```

Production prints its target and requires typing `hetzner`:

```bash
./deploy/bootstrap.sh hetzner
```

Intentional non-interactive production automation may use `--yes`. Use it only
when the caller already provides an equivalent approval boundary.

Options:

- `--dry-run` validates local input and live prerequisites, verifies kubectl can
  consume the env file, and renders the bootstrap chart without changing the
  cluster.
- `--no-wait` returns after applying the namespace, Secret, and Argo resources.
  Reconciliation continues asynchronously in Argo CD.
- `--yes` bypasses only the typed Hetzner confirmation. It does not bypass input,
  prerequisite, or TLS validation.

Without `--no-wait`, bootstrap waits up to ten minutes for the Application to be
Synced and Healthy, exactly three available Deployment replicas, and a Ready
Certificate. A timeout prints only non-secret controller/resource statuses and
recent namespace events.

## Secret ownership and rotation

Bootstrap reads the env file without sourcing it and applies
`planner-runtime-env` directly through kubectl stdin. Secret values are not
passed as command arguments, Helm values, Argo CD parameters, or repository
content. Only a canonical SHA-256 digest is passed to the Application. Changing
actual credentials changes that pod-template annotation and triggers an
Argo-managed rolling update; comments and entry ordering do not.

Rotate a credential by updating the ignored target env file and rerunning the
same bootstrap command. Changing `SESSION_COOKIE_KEY` invalidates existing
Google Account Connections, so rotate it deliberately. All three replicas must
always share the same key.

## Reconciliation boundary

Both Applications track `main` with automatic sync, pruning, self-healing, and
five exponential retries. Once bootstrapped, image and chart releases happen by
changing Git desired state; do not run a local Helm upgrade for the Planner
workload. Bootstrap Helm owns only the AppProject and Application.

A failed workload rollout remains degraded in Argo CD while healthy old replicas
continue serving. Nothing automatically changes Git. Traefik's sticky cookie
protects browsers from mixed-version SPA assets during a rollout; Planner's
Google Account Connection remains stateless across replicas.

HTTP-to-HTTPS redirection is cluster-global and is not created by the Planner
chart. The chart creates only the `websecure` route and cert-manager Certificate.

## Image publication and staging

Pull requests run the application tests and typecheck, deployment-tool tests,
Helm lint/render checks for both environments, ShellCheck, actionlint, and a
production-image smoke test. The smoke test runs the image as uid/gid 10001 on
a read-only root filesystem and verifies health, runtime configuration, SPA
serving, and fail-fast OAuth validation.

A merge to `main` publishes only when a container input changes. It builds
`linux/amd64` and `linux/arm64` as one public GHCR image tagged with the source
revision in `sha-abcdef0` form. An OCI candidate is scanned before release tags
are attached: fixable CRITICAL findings block publication, while HIGH and
unfixable findings are reported. Published SHA images include OCI provenance and
an SBOM. The candidate is pushed under a non-release build tag so both platform
variants can be scanned by digest; only that exact approved digest receives the
immutable SHA release tag.

The first successful publication may create a private GHCR package even though
the repository is public. A repository owner must open the package settings,
set visibility to **Public**, link it to this repository if necessary, and prove
that `ghcr.io/yet-an-other/planner2:sha-abcdef0` can be pulled without logging in.
Clusters deliberately have no image-pull Secret.

Every eligible merge keeps its immutable SHA image. A serialized release step
rechecks current `main`; only the newest commit affecting container inputs may
move `latest` and update the Proxmox image value. Superseded builds never move
staging backward. The update is a narrow `[skip ci]` commit to `main`, after
which staging Argo CD reconciles it. Repository rules must allow the workflow's
`GITHUB_TOKEN` to make that narrowly scoped commit with `contents: write`; do
not substitute a broad personal access token.

## Production promotion

Create a protected GitHub Environment named `production` and configure its
required reviewers before the first production release. The **Promote
production** workflow is manually dispatched and pauses at that environment. It
takes no image input: after approval it copies the exact immutable image
currently declared for Proxmox into Hetzner desired state and commits only that
value to `main`.

Promotion does not rebuild the image and does not contact either cluster or the
public staging URL. The approving operator is responsible for confirming
staging health before approval. Chart and infrastructure changes are not part of
this image gate; both Argo CD Applications intentionally track `main`.

## Production rollback

The **Roll back production** workflow is also manually dispatched under the
protected `production` Environment. It walks the Hetzner value's Git history,
restores the immediately previous distinct immutable image, and commits only
that value. Repeated approved runs continue backward through the production
release stack. It fails safely when no earlier release exists and never changes
Proxmox, `latest`, or chart/infrastructure state.

Promotion and rollback share one serialized production concurrency boundary,
fetch current `main`, and retry a raced push without discarding unrelated
changes. Their normal Git commits are the production audit trail; Argo CD applies
them after the workflow succeeds.
