#!/usr/bin/env bash
set -euo pipefail

image=${1:?Usage: container-smoke.sh IMAGE}
client_id=smoke.apps.googleusercontent.com
client_secret=private-smoke-secret
cookie_key=abababababababababababababababababababababababababababababababab
product_version=sha-abcdef0
container=

cleanup() {
  if [[ -n "$container" ]]; then
    docker rm -f "$container" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

user=$(docker image inspect --format '{{.Config.User}}' "$image")
[[ "$user" == 10001:10001 ]] || {
  printf 'expected image user 10001:10001, got %s\n' "$user" >&2
  exit 1
}

container=$(docker run --detach --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  --publish 127.0.0.1::3000 \
  --env "VITE_GOOGLE_CLIENT_ID=$client_id" \
  --env "GOOGLE_CLIENT_ID=$client_id" \
  --env "GOOGLE_CLIENT_SECRET=$client_secret" \
  --env "SESSION_COOKIE_KEY=$cookie_key" \
  --env "APP_VERSION=$product_version" \
  "$image")

mapping=$(docker port "$container" 3000/tcp | tail -n 1)
port=${mapping##*:}
base_url="http://127.0.0.1:$port"

for _ in $(seq 1 30); do
  if curl --fail --silent --show-error "$base_url/healthz" >/tmp/planner-health.json 2>/dev/null; then
    break
  fi
  if [[ $(docker inspect --format '{{.State.Running}}' "$container") != true ]]; then
    docker logs "$container" >&2
    exit 1
  fi
  sleep 1
done

health=$(curl --fail --silent --show-error "$base_url/healthz")
[[ "$health" == *'"status":"ok"'* && "$health" == *"\"productVersion\":\"$product_version\""* ]] || {
  printf 'unexpected health response: %s\n' "$health" >&2
  exit 1
}

runtime_config=$(curl --fail --silent --show-error "$base_url/runtime-config.js")
[[ "$runtime_config" == *"$client_id"* && "$runtime_config" == *"$product_version"* ]] || {
  printf 'runtime configuration did not contain its public contract\n' >&2
  exit 1
}
[[ "$runtime_config" != *"$client_secret"* && "$runtime_config" != *"$cookie_key"* ]] || {
  printf 'runtime configuration exposed a private value\n' >&2
  exit 1
}

spa=$(curl --fail --silent --show-error "$base_url/")
[[ "$spa" == *'<div id="root"></div>'* ]] || {
  printf 'SPA shell was not served\n' >&2
  exit 1
}

cleanup
container=
if docker run --rm \
  --env VITE_GOOGLE_CLIENT_ID=browser.apps.googleusercontent.com \
  --env GOOGLE_CLIENT_ID=server.apps.googleusercontent.com \
  --env "GOOGLE_CLIENT_SECRET=$client_secret" \
  --env "SESSION_COOKIE_KEY=$cookie_key" \
  --env "APP_VERSION=$product_version" \
  "$image" >/tmp/planner-invalid-config.log 2>&1; then
  printf 'image accepted mismatched Google client ids\n' >&2
  exit 1
fi

grep -q 'VITE_GOOGLE_CLIENT_ID must match GOOGLE_CLIENT_ID' /tmp/planner-invalid-config.log
printf 'Planner container smoke test passed.\n'
