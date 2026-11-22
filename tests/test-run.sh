#!/usr/bin/env bash
# A missing login logs one link. A finished login execs connect, with --debug only at debug.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
work=$(mktemp -d)
pid=""
cleanup() {
  if [[ -n "$pid" ]]; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

unset GROKBOT_STORE
export GROKBOT_HOME="${work}/home"
export HOME="$GROKBOT_HOME"
export GROKBOT_STATE_DIR="${work}/run"
export GROKBOT_OPTIONS_FILE="${work}/options.json"
export GROKBOT_BIN="${work}/bin/grokbot-tunnel"
export GROKBOT_FAKE_COUNT="${work}/login.count"
export GROKBOT_ARGS_FILE="${work}/args"
mkdir -p "$(dirname "$GROKBOT_BIN")" "$GROKBOT_STATE_DIR" "$GROKBOT_HOME"
cp "${root}/tests/fixtures/fake-grokbot-tunnel" "$GROKBOT_BIN"
chmod 0755 "$GROKBOT_BIN"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "${work}/log" ]]; then
    printf '%s\n' "--- log ---" >&2
    cat "${work}/log" >&2
  fi
  exit 1
}

stop_run() {
  if [[ -n "$pid" ]]; then
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    pid=""
  fi
}

write_options() {
  printf '%s\n' "{\"label\":\"homeassistant\",\"auto_update\":false,\"log_level\":\"${1}\"}" \
    > "$GROKBOT_OPTIONS_FILE"
}

start_run() {
  rm -f "$GROKBOT_ARGS_FILE" "${work}/log" "$GROKBOT_FAKE_COUNT" \
    "${GROKBOT_STATE_DIR}/status.json" "${GROKBOT_STATE_DIR}/login.out" "${GROKBOT_STATE_DIR}/qr.svg"
  rm -rf "${GROKBOT_HOME}/.grok"
  setsid "${root}/grokbot_client/rootfs/usr/lib/grokbot/run.sh" >"${work}/log" 2>&1 &
  pid=$!
}

wait_for() {
  local file="$1"
  for _ in $(seq 1 40); do
    if [[ -s "$file" ]]; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

write_options info
start_run
wait_for "$GROKBOT_ARGS_FILE" || fail "info run did not connect"
if grep -q -- '--permission' "$GROKBOT_ARGS_FILE"; then
  fail "permission was passed"
fi
grep -q -- '--label homeassistant' "$GROKBOT_ARGS_FILE" || fail "label was not passed"
grep -q -- '--root /' "$GROKBOT_ARGS_FILE" || fail "root was not passed"
if grep -q -- '--debug' "$GROKBOT_ARGS_FILE"; then
  fail "info passed --debug"
fi
[[ "$(jq -r '.status' "${GROKBOT_STATE_DIR}/status.json")" == "Connected as homeassistant" ]] || fail "status was not connected"
[[ "$(jq -r '.email' "${GROKBOT_STATE_DIR}/status.json")" == "owner@example.com" ]] || fail "email missing"
[[ "$(grep -c 'Sign-in link:' "${work}/log")" == "1" ]] || fail "sign-in link was not logged once"
stop_run

write_options debug
start_run
wait_for "$GROKBOT_ARGS_FILE" || fail "debug run did not connect"
grep -q -- '--debug' "$GROKBOT_ARGS_FILE" || fail "debug did not pass --debug"
stop_run

write_options warning
start_run
wait_for "$GROKBOT_ARGS_FILE" || fail "warning run did not connect"
if grep -q -- '--debug' "$GROKBOT_ARGS_FILE"; then
  fail "warning passed --debug"
fi
stop_run

unset GROKBOT_FAKE_COUNT
write_options info
rm -f "$GROKBOT_ARGS_FILE" "${work}/log" \
  "${GROKBOT_STATE_DIR}/status.json" "${GROKBOT_STATE_DIR}/login.out" "${GROKBOT_STATE_DIR}/qr.svg"
rm -rf "${GROKBOT_HOME}/.grok"
env -u GROKBOT_FAKE_COUNT setsid "${root}/grokbot_client/rootfs/usr/lib/grokbot/run.sh" >"${work}/log" 2>&1 &
pid=$!
wait_for "${GROKBOT_STATE_DIR}/status.json" || fail "waiting status was not written"
[[ "$(jq -r '.status' "${GROKBOT_STATE_DIR}/status.json")" == "Waiting for sign-in" ]] || fail "missing login did not wait"
[[ "$(jq -r '.login_url' "${GROKBOT_STATE_DIR}/status.json")" == https://example.test/* ]] || fail "login url missing"
[[ "$(grep -c 'Sign-in link:' "${work}/log")" == "1" ]] || fail "waiting link was not logged once"
stop_run

printf '%s\n' "run tests passed"
