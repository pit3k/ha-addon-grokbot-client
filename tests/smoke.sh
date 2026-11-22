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
  "$image" >/dev/null

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  docker logs "$name" >&2 || true
  exit 1
}

page=""
for _ in $(seq 1 40); do
  if page=$(docker exec "$name" curl -fsS "http://127.0.0.1:8099/" 2>/dev/null); then
    break
  fi
  sleep 0.5
done
[[ -n "$page" ]] || fail "panel did not start"
grep -q 'id="status"' <<<"$page" || fail "panel page has no status"
grep -q 'id="signout"' <<<"$page" || fail "panel page has no sign-out button"

status=""
for _ in $(seq 1 40); do
  status=$(docker exec "$name" curl -fsS "http://127.0.0.1:8099/cgi-bin/status" 2>/dev/null || true)
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

ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
denied=$(docker run --rm --network bridge --entrypoint wget "$image" -S -O /dev/null "http://${ip}:8099/cgi-bin/status" 2>&1 || true)
grep -q '403 Forbidden' <<<"$denied" || fail "a non-ingress address was not refused"

printf '%s\n' "smoke test passed"
