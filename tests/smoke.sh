#!/usr/bin/env bash
# Run the app image and check the panel plus a missing login.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
image="${GROKBOT_IMAGE:-}"
if [[ -z "$image" ]]; then
  image="grokbot-client:test"
  docker build \
    --build-arg BUILD_ARCH=amd64 \
    --build-arg BUILD_VERSION=0.1.0 \
    -t "$image" \
    "${root}/grokbot_client"
fi

if ! command -v docker >/dev/null 2>&1; then
  printf '%s\n' "docker is required for the smoke test" >&2
  exit 1
fi

work=$(mktemp -d)
name="grokbot-smoke-$$"
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "${work}/data/.local/bin" "${work}/data/.grok"
cp "${root}/tests/fixtures/fake-grokbot-tunnel" "${work}/data/.local/bin/grokbot-tunnel"
chmod 0755 "${work}/data/.local/bin/grokbot-tunnel"
printf '%s\n' '{"permission":"always","label":"ha","auto_update":false}' > "${work}/data/options.json"

docker run -d --name "$name" \
  -v "${work}/data:/data" \
  -p 127.0.0.1::8099 \
  "$image" >/dev/null

port=$(docker port "$name" 8099/tcp | awk -F: 'NR==1 { print $NF }')
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  docker logs "$name" >&2 || true
  exit 1
}

page=""
for _ in $(seq 1 40); do
  if page=$(curl -fsS "http://127.0.0.1:${port}/" 2>/dev/null); then
    break
  fi
  sleep 0.5
done
[[ -n "$page" ]] || fail "panel did not start"
grep -q "Sign in" <<<"$page" || fail "panel page has no sign-in button"

status=""
for _ in $(seq 1 40); do
  status=$(curl -fsS "http://127.0.0.1:${port}/api/status" 2>/dev/null || true)
  if [[ "$(jq -r '.status' <<<"$status" 2>/dev/null || true)" == "Waiting for sign-in" ]]; then
    break
  fi
  sleep 0.5
done
[[ "$(jq -r '.status' <<<"$status")" == "Waiting for sign-in" ]] || fail "status did not show a missing login: $status"
url=$(jq -r '.login_url' <<<"$status")
[[ "$url" == https://example.test/* ]] || fail "login url missing: $status"

logs=$(docker logs "$name" 2>&1 || true)
grep -F "Sign-in link: ${url}" <<<"$logs" >/dev/null || fail "log did not mirror the sign-in link"
if grep -q "refresh_token" <<<"$logs"; then
  fail "log contains refresh_token"
fi
if grep -q "super-secret-token-value" <<<"$logs"; then
  fail "log contains a token"
fi

printf '%s\n' "smoke test passed"
