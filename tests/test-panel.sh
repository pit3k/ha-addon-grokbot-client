#!/usr/bin/env bash
# The panel binary serves the page and accepts sign-in controls.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
work=$(mktemp -d)
pid=""
cleanup() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

gcc -std=c11 -Os -Wall -Wextra -Werror \
  -o "${work}/panel" "${root}/grokbot_client/panel/server.c"

export GROKBOT_PANEL_PORT=0
# Pick a free port by binding from python, then reuse it. The server binds a fixed port.
port=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)
export GROKBOT_PANEL_PORT="$port"
export GROKBOT_PANEL_ROOT="${root}/grokbot_client/rootfs/opt/panel"
export GROKBOT_STATE_DIR="${work}/run"
mkdir -p "$GROKBOT_STATE_DIR"
jq -n \
  --arg status "Waiting for sign-in" \
  --arg url "https://example.test/loginDeepControl?challenge=abc" \
  '{state:"waiting",status:$status,login_url:$url,error:"",detail:"",version:"grokbot-tunnel v9.9.9 (test)",email:"",label:"ha"}' \
  > "${GROKBOT_STATE_DIR}/status.json"

"${work}/panel" &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

page=$(curl -fsS "http://127.0.0.1:${port}/")
grep -q "Grok Bot client" <<<"$page" || fail "page title missing"
grep -q 'id="signout"[^>]*hidden' <<<"$page" || fail "Sign out starts visible"
grep -q 'Click to sign in' <<<"$page" || fail "sign-in link missing"
grep -q 'id="copy"[^>]*hidden' <<<"$page" || fail "Copy starts visible"
buttons=$(grep -c '<button' <<<"$page")
[[ "$buttons" == "2" ]] || fail "expected two buttons, found ${buttons}"
css=$(curl -fsS "http://127.0.0.1:${port}/style.css")
grep -q '\[hidden\]' <<<"$css" || fail "hidden rule missing"
grep -q 'display: none !important' <<<"$css" || fail "hidden does not override display"
grep -q 'prefers-color-scheme: dark' <<<"$css" || fail "dark scheme missing"
js=$(curl -fsS "http://127.0.0.1:${port}/app.js")
grep -q 'show(signout, connected)' <<<"$js" || fail "Sign out is not limited to connected"
grep -q 'addEventListener("error"' <<<"$js" || fail "QR load is not retried"
if grep -q 'api/sign-in' <<<"$js"; then
  fail "panel still requests sign-in"
fi

code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/qr.svg")
[[ "$code" == "404" ]] || fail "missing qr returned ${code}"
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg"></svg>' > "${GROKBOT_STATE_DIR}/qr.svg"
curl -fsS -D "${work}/qr.hdr" -o "${work}/qr.body" "http://127.0.0.1:${port}/qr.svg"
grep -qi 'image/svg+xml' "${work}/qr.hdr" || fail "qr content type"
if grep -qi 'Content-Security-Policy' "${work}/qr.hdr"; then
  fail "qr response carries the page policy"
fi
grep -q '<svg' "${work}/qr.body" || fail "qr body"
rm -f "${GROKBOT_STATE_DIR}/qr.svg"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/qr.svg")
[[ "$code" == "404" ]] || fail "removed qr returned ${code}"
printf '%s\n' '<svg xmlns="http://www.w3.org/2000/svg" id="again"></svg>' > "${GROKBOT_STATE_DIR}/qr.svg"
body=$(curl -fsS "http://127.0.0.1:${port}/qr.svg?t=2")
grep -q 'id="again"' <<<"$body" || fail "qr was not served again"

status=$(curl -fsS "http://127.0.0.1:${port}/api/status")
[[ "$(jq -r '.status' <<<"$status")" == "Waiting for sign-in" ]] || fail "status payload"
[[ "$(jq -r '.login_url' <<<"$status")" == https://example.test/* ]] || fail "status url"

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${port}/api/sign-out")
[[ "$code" == "403" ]] || fail "missing panel header was ${code}"

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "X-Grokbot-Panel: 1" \
  "http://127.0.0.1:${port}/api/sign-in")
[[ "$code" == "204" ]] || fail "sign-in returned ${code}"
[[ "$(tr -d '[:space:]' < "${GROKBOT_STATE_DIR}/control")" == "sign-in" ]] || fail "control file"
rm -f "${GROKBOT_STATE_DIR}/control"

jq -n '{state:"connected",status:"Connected as ha",login_url:"",error:"",detail:"",version:"v",email:"owner@example.com",label:"ha"}' \
  > "${GROKBOT_STATE_DIR}/status.json"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "X-Grokbot-Panel: 1" \
  "http://127.0.0.1:${port}/api/sign-in")
[[ "$code" == "204" ]] || fail "connected sign-in returned ${code}"
[[ ! -e "${GROKBOT_STATE_DIR}/control" ]] || fail "connected sign-in wrote a control file"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "X-Grokbot-Panel: 1" \
  "http://127.0.0.1:${port}/api/sign-out")
[[ "$code" == "204" ]] || fail "sign-out returned ${code}"
[[ "$(tr -d '[:space:]' < "${GROKBOT_STATE_DIR}/control")" == "sign-out" ]] || fail "sign-out control"

code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/../etc/passwd")
[[ "$code" == "404" || "$code" == "400" ]] || fail "path traversal returned ${code}"

printf '%s\n' "panel tests passed"
