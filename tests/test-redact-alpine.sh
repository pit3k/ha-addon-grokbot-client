#!/usr/bin/env bash
# Redaction must work with BusyBox grep, which is what the add-on image ships.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  printf '%s\n' "docker is required to test BusyBox redaction" >&2
  exit 1
fi

out=$(docker run --rm --entrypoint bash \
  -v "${root}/grokbot_client/rootfs/usr/lib/grokbot/common.sh:/common.sh:ro" \
  ghcr.io/home-assistant/base:3.24 \
  -c '
    set -o pipefail
    source /common.sh
    tmp=$(mktemp)
    printf "%s\n" \
      "not logged in" \
      "refresh_token=super-secret-token-value" \
      "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature" \
      "plain error" > "$tmp"
    grok_tail_error "$tmp"
  ')

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  printf '%s\n' "$out" >&2
  exit 1
}

grep -q "not logged in" <<<"$out" || fail "dropped the error"
grep -q "plain error" <<<"$out" || fail "dropped the second error"
if grep -q "super-secret-token-value" <<<"$out"; then
  fail "kept the refresh token"
fi
if grep -q "eyJ" <<<"$out"; then
  fail "kept a bearer token"
fi
printf '%s\n' "alpine redaction passed"
