#!/usr/bin/env bash
# The service loop: missing login surfaces a link, and sign-out drops the tokens.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
work=$(mktemp -d)
pid=""
cleanup() {
  if [[ -n "$pid" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

export HOME="${work}/home"
export GROKBOT_HOME="$HOME"
export GROKBOT_STORE="${HOME}/.grok/bot-tunnel"
export GROKBOT_STATE_DIR="${work}/run"
export GROKBOT_OPTIONS_FILE="${work}/options.json"
export GROKBOT_BIN="${work}/bin/grokbot-tunnel"
export GROKBOT_COMMON="${root}/grokbot_client/rootfs/usr/lib/grokbot/common.sh"
export GROKBOT_FAKE_COUNT="${work}/login.count"
mkdir -p "$(dirname "$GROKBOT_BIN")" "$GROKBOT_STATE_DIR" "$HOME"
cp "${root}/tests/fixtures/fake-grokbot-tunnel" "$GROKBOT_BIN"
chmod 0755 "$GROKBOT_BIN"
printf '%s\n' '{"permission":"always","label":"ha","auto_update":false}' > "$GROKBOT_OPTIONS_FILE"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "${work}/log" ]]; then
    printf '%s\n' "--- log ---" >&2
    cat "${work}/log" >&2
  fi
  exit 1
}

wait_status() {
  local want="$1"
  for _ in $(seq 1 40); do
    if [[ -f "${GROKBOT_STATE_DIR}/status.json" ]] &&
      jq -e --arg want "$want" '.status == $want' "${GROKBOT_STATE_DIR}/status.json" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

setsid "${root}/grokbot_client/rootfs/usr/lib/grokbot/run.sh" >"${work}/log" 2>&1 &
pid=$!

wait_status "Connected as ha" || fail "did not connect"
email=$(jq -r '.email' "${GROKBOT_STATE_DIR}/status.json")
[[ "$email" == "owner@example.com" ]] || fail "email missing"
if grep -q "super-secret-token-value" "${work}/log"; then
  fail "token was written to the log"
fi
if grep -q "also-secret" "${work}/log"; then
  fail "access token was written to the log"
fi

control_tmp=$(mktemp "${GROKBOT_STATE_DIR}/control.XXXXXX")
printf '%s\n' "sign-out" >"$control_tmp"
mv -f "$control_tmp" "${GROKBOT_STATE_DIR}/control"
url=""
for _ in $(seq 1 40); do
  if [[ ! -e "${GROKBOT_STORE}/auth.json" ]] && [[ -f "${GROKBOT_STATE_DIR}/status.json" ]]; then
    url=$(jq -r '.login_url' "${GROKBOT_STATE_DIR}/status.json")
    if [[ "$url" == https://example.test/* && "$(jq -r '.status' "${GROKBOT_STATE_DIR}/status.json")" == "Waiting for sign-in" ]]; then
      break
    fi
  fi
  url=""
  sleep 0.25
done
[[ -n "$url" ]] || fail "sign-out did not return to a sign-in link"
[[ ! -e "${GROKBOT_STORE}/auth.json" ]] || fail "auth.json survived sign-out"
grep -F "Sign-in link: ${url}" "${work}/log" >/dev/null || fail "sign-in link was not mirrored to the log"

printf '%s\n' "session tests passed"
