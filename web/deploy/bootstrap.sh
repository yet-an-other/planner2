#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s <proxmox|hetzner> [--dry-run] [--no-wait] [--yes]\n' "${0##*/}" >&2
}

fail() {
  printf 'planner bootstrap: %s\n' "$*" >&2
  exit 1
}

if (( $# < 1 )); then
  usage
  exit 2
fi

cluster=$1
shift
case "$cluster" in
  proxmox|hetzner) ;;
  *) usage; fail "cluster must be proxmox or hetzner" ;;
esac

dry_run=false
wait_for_ready=true
confirmed=false
while (( $# > 0 )); do
  case "$1" in
    --dry-run) dry_run=true ;;
    --no-wait) wait_for_ready=false ;;
    --yes) confirmed=true ;;
    *) usage; fail "unknown option: $1" ;;
  esac
  shift
done

for dependency in node kubectl helm; do
  command -v "$dependency" >/dev/null 2>&1 || fail "required command not found: $dependency"
done

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
env_file="$script_dir/.env.$cluster"
kubeconfig="$HOME/remote-kube/$cluster/config"
bootstrap_chart="$script_dir/charts/planner-bootstrap"
bootstrap_values="$bootstrap_chart/values-$cluster.yaml"
env_validator="$script_dir/scripts/runtime-env.mjs"
release_state="$script_dir/scripts/release-state.mjs"
repo_root=$(dirname "$script_dir")

[[ -f "$env_file" ]] || fail "runtime environment file not found: $env_file"
[[ -f "$kubeconfig" ]] || fail "kubeconfig not found: $kubeconfig"
[[ -f "$env_validator" ]] || fail "runtime environment validator not found"
[[ -f "$release_state" ]] || fail "release state validator not found"
[[ -f "$bootstrap_values" ]] || fail "bootstrap values not found for $cluster"

# The validator emits only a canonical digest. It never evaluates the env file
# or prints values, so this is safe to pass to Helm as a rollout parameter.
runtime_checksum=$(node "$env_validator" "$env_file")
[[ "$runtime_checksum" =~ ^[0-9a-f]{64}$ ]] || fail "runtime environment validator returned an invalid checksum"
desired_image=$(cd "$repo_root" && node deploy/scripts/release-state.mjs current "$cluster")
[[ "$desired_image" != sha-0000000 ]] || fail "$cluster image has not been released; publish or promote an immutable image before bootstrap"

if [[ "$cluster" == hetzner && "$confirmed" != true ]]; then
  printf 'Production target: Hetzner (planner.ivan-b.com). Type hetzner to continue: ' >&2
  IFS= read -r answer || fail "production confirmation was not provided"
  [[ "$answer" == hetzner ]] || fail "production confirmation did not match hetzner"
fi

kube() {
  kubectl --kubeconfig "$kubeconfig" "$@"
}

printf 'Checking %s cluster prerequisites with verified Kubernetes API TLS...\n' "$cluster"
kube version --request-timeout=10s >/dev/null
kube get namespace argocd >/dev/null
for crd in \
  applications.argoproj.io \
  appprojects.argoproj.io \
  ingressroutes.traefik.io \
  certificates.cert-manager.io; do
  kube get crd "$crd" >/dev/null
done
issuer_ready=$(kube get clusterissuer letsencrypt-dns -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}')
[[ "$issuer_ready" == True ]] || fail "ClusterIssuer letsencrypt-dns is not Ready"

if [[ "$dry_run" == true ]]; then
  # Validate kubectl's env-file handling without printing Secret YAML or making
  # an API mutation, then render the exact Argo resources Helm would install.
  kube create secret generic planner-runtime-env \
    --namespace planner \
    --from-env-file="$env_file" \
    --dry-run=client \
    -o name >/dev/null
  helm template planner "$bootstrap_chart" \
    --namespace argocd \
    -f "$bootstrap_values" \
    --set-string "runtimeChecksum=$runtime_checksum" >/dev/null
  printf 'Dry run succeeded for %s; no resources were changed.\n' "$cluster"
  exit 0
fi

printf 'Applying Planner namespace and external runtime Secret...\n'
kube create namespace planner --dry-run=client -o yaml | kube apply -f - >/dev/null
# Values remain in the ignored file and flow only over stdin to kubectl apply.
# They are never shell-expanded into arguments or stored in Helm/Argo values.
kube create secret generic planner-runtime-env \
  --namespace planner \
  --from-env-file="$env_file" \
  --dry-run=client \
  -o yaml | kube apply -f - >/dev/null

printf 'Installing Planner Argo CD bootstrap resources...\n'
helm upgrade --install planner "$bootstrap_chart" \
  --kubeconfig "$kubeconfig" \
  --namespace argocd \
  -f "$bootstrap_values" \
  --set-string "runtimeChecksum=$runtime_checksum" >/dev/null

if [[ "$wait_for_ready" != true ]]; then
  printf 'Bootstrap applied. Reconciliation continues in Argo CD.\n'
  exit 0
fi

timeout_seconds=${PLANNER_BOOTSTRAP_TIMEOUT_SECONDS:-600}
poll_seconds=${PLANNER_BOOTSTRAP_POLL_SECONDS:-5}
[[ "$timeout_seconds" =~ ^[0-9]+$ ]] || fail "bootstrap timeout must be a non-negative integer"
[[ "$poll_seconds" =~ ^[0-9]+$ ]] || fail "bootstrap poll interval must be a non-negative integer"
deadline=$((SECONDS + timeout_seconds))

printf 'Waiting up to ten minutes for Planner to become ready...\n'
while true; do
  application_status=$(kube --namespace argocd get application planner \
    -o 'jsonpath={.status.sync.status} {.status.health.status}' 2>/dev/null || true)
  available_replicas=$(kube --namespace planner get deployment planner \
    -o 'jsonpath={.status.availableReplicas}' 2>/dev/null || true)
  certificate_ready=$(kube --namespace planner get certificate planner \
    -o 'jsonpath={.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)

  if [[ "$application_status" == 'Synced Healthy' && \
        "$available_replicas" == 3 && \
        "$certificate_ready" == True ]]; then
    printf 'Planner is Synced and Healthy with three available replicas and a Ready Certificate.\n'
    exit 0
  fi

  if (( SECONDS >= deadline )); then
    printf 'planner bootstrap: timed out waiting for Planner readiness. Current non-secret status:\n' >&2
    printf 'Argo CD Application: ' >&2
    kube --namespace argocd get application planner >&2 || true
    printf 'Planner Deployment: ' >&2
    kube --namespace planner get deployment planner >&2 || true
    printf 'Planner Certificate: ' >&2
    kube --namespace planner get certificate planner >&2 || true
    printf 'Recent Planner namespace events:\n' >&2
    kube --namespace planner get events --sort-by=.lastTimestamp >&2 || true
    exit 1
  fi

  sleep "$poll_seconds"
done
