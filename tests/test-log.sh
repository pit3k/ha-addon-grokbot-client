#!/usr/bin/env bash
# Log level selects grokbot-tunnel --debug and whether its stderr is forwarded.
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
export GROKBOT_ARGS_FILE="${work}/args"
export GROKBOT_FAKE_COUNT="${work}/login.count"
mkdir -p "$(dirname "$GROKBOT_BIN")" "$GROKBOT_STATE_DIR" "$HOME"
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

run_until_connected() {
  local level="$1"
  printf '%s\n' "{\"permission\":\"always\",\"label\":\"ha\",\"auto_update\":false,\"log_level\":\"${level}\"}" \
    > "$GROKBOT_OPTIONS_FILE"
  rm -f "$GROKBOT_ARGS_FILE" "${work}/log" "$GROKBOT_FAKE_COUNT"
  rm -rf "$GROKBOT_STORE"
  setsid "${root}/grokbot_client/rootfs/usr/lib/grokbot/run.sh" >"${work}/log" 2>&1 &
  pid=$!
  for _ in $(seq 1 40); do
    if [[ -s "$GROKBOT_ARGS_FILE" ]]; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

stop_run() {
  if [[ -n "$pid" ]]; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    pid=""
  fi
}

run_until_connected warning || fail "warning run did not connect"
sleep 1.5
if grep -q "request 1: echo hi" "${work}/log"; then
  fail "warning forwarded a client request"
fi
if grep -q -- '--debug' "$GROKBOT_ARGS_FILE"; then
  fail "warning passed --debug"
fi
if grep -q "refresh_token" "${work}/log"; then
  fail "warning log kept a token"
fi
stop_run

run_until_connected debug || fail "debug run did not connect"
sleep 1.5
grep -q -- '--debug' "$GROKBOT_ARGS_FILE" || fail "debug did not pass --debug"
grep -q "request 1: echo hi" "${work}/log" || fail "debug missed the client request"
if grep -q "refresh_token" "${work}/log"; then
  fail "debug log kept a token"
fi
stop_run

printf '%s\n' "log level tests passed"
