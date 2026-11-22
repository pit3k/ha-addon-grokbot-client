#!/usr/bin/env bash
# Login state, sign-out, URL capture, and redaction. Tokens must not be printed.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME="${work}/home"
export GROKBOT_STORE="${HOME}/.grok/bot-tunnel"
export GROKBOT_STATE_DIR="${work}/run"
export GROKBOT_BIN="${work}/bin/grokbot-tunnel"
mkdir -p "$GROKBOT_STORE" "$GROKBOT_STATE_DIR" "$(dirname "$GROKBOT_BIN")"

# shellcheck source=../grokbot_client/rootfs/usr/lib/grokbot/common.sh
source "${root}/grokbot_client/rootfs/usr/lib/grokbot/common.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

secret="super-secret-token-value"
if grok_logged_in; then
  fail "empty store looked signed in"
fi

printf '%s\n' "{\"refresh_token\":\"${secret}\",\"access_token\":\"also-secret\",\"email\":\"owner@example.com\"}" \
  > "${GROKBOT_STORE}/auth.json"
printf '%s\n' '{"credential":"computer-secret"}' > "${GROKBOT_STORE}/computer.json"
printf '%s\n' '{"machine_id":"keep-me"}' > "${GROKBOT_STORE}/machine.json"

capture="${work}/capture"
{
  grok_logged_in
  grok_account_email
} >"$capture" 2>&1
if grep -q "$secret" "$capture"; then
  fail "token was printed"
fi
[[ "$(grok_account_email)" == "owner@example.com" ]] || fail "email was not read"
grok_logged_in || fail "refresh token was not accepted"

grok_wipe_login
[[ ! -e "${GROKBOT_STORE}/auth.json" ]] || fail "auth.json survived sign-out"
[[ ! -e "${GROKBOT_STORE}/computer.json" ]] || fail "computer.json survived sign-out"
[[ -f "${GROKBOT_STORE}/machine.json" ]] || fail "machine.json was removed"
if grok_logged_in; then
  fail "wiped store still looked signed in"
fi

printf '%s\n' '{"refresh_token":"","email":"nobody@example.com"}' > "${GROKBOT_STORE}/auth.json"
if grok_logged_in; then
  fail "empty refresh token looked signed in"
fi

sample="${work}/login.out"
cat > "$sample" <<'EOF'
Open this URL to sign in:
https://example.test/loginDeepControl?challenge=abc&uuid=11111111-1111-1111-1111-111111111111&mode=login

Logged in as owner@example.com
EOF
url=$(grok_extract_url "$sample")
expected="https://example.test/loginDeepControl?challenge=abc&uuid=11111111-1111-1111-1111-111111111111&mode=login"
[[ "$url" == "$expected" ]] || fail "url parse: $url"

redacted="${work}/redacted"
cat > "${work}/err" <<EOF
not logged in
refresh_token=${secret}
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature
plain error
EOF
grok_tail_error "${work}/err" > "$redacted"
grep -q "not logged in" "$redacted" || fail "redaction dropped the error"
grep -q "plain error" "$redacted" || fail "redaction dropped the second error"
if grep -q "$secret" "$redacted"; then
  fail "redaction kept the refresh token"
fi
if grep -q "eyJ" "$redacted"; then
  fail "redaction kept a bearer token"
fi

stub="${work}/bin"
mkdir -p "$stub"
cat > "${stub}/qrencode" <<'EOF'
#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then
    out="$arg"
  fi
  prev="$arg"
done
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg"></svg>' > "$out"
EOF
chmod 0755 "${stub}/qrencode"
PATH="${stub}:${PATH}" grok_write_qr "https://example.test/login"
[[ -s "${GROKBOT_STATE_DIR}/qr.svg" ]] || fail "qr was not written"
grep -q '<svg' "${GROKBOT_STATE_DIR}/qr.svg" || fail "qr file is empty"

export GROKBOT_OPTIONS_FILE="${work}/options.json"
printf '%s\n' '{"log_level":"warning"}' > "$GROKBOT_OPTIONS_FILE"
grok_forwards_client_log && fail "warning forwards the client log"
printf '%s\n' '{"log_level":"debug"}' > "$GROKBOT_OPTIONS_FILE"
grok_forwards_client_log || fail "debug does not forward the client log"
[[ "$(grok_normalize_log_level "$(grok_option log_level info)")" == "debug" ]] || fail "debug level"

printf '%s\n' "login tests passed"
