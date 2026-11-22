#!/usr/bin/env bash
# BusyBox httpd serves the page. A CGI script answers status and sign-out.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
panel="${root}/grokbot_client/rootfs/opt/panel"
conf="${root}/grokbot_client/rootfs/etc/grokbot/httpd.conf"
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

if command -v httpd >/dev/null 2>&1; then
  httpd=(httpd)
else
  httpd=(busybox httpd)
fi

port=$(python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)
export GROKBOT_STATE_DIR="${work}/run"
export GROKBOT_STORE="${work}/store"
export GROKBOT_PERMISSION_FILE="${work}/permission"
mkdir -p "${work}/www/cgi-bin" "$GROKBOT_STATE_DIR" "$GROKBOT_STORE"
ln -s "${panel}/index.html" "${panel}/style.css" "${panel}/app.js" "${work}/www/"
ln -s "${panel}/cgi-bin/status" "${work}/www/cgi-bin/status"
ln -s status "${work}/www/cgi-bin/sign-out"
ln -s status "${work}/www/cgi-bin/permission"
ln -s "${GROKBOT_STATE_DIR}/qr.svg" "${work}/www/qr.svg"
jq -n \
  --arg status "Waiting for sign-in" \
  --arg url "https://example.test/loginDeepControl?challenge=abc" \
  '{state:"waiting",status:$status,login_url:$url,error:"",detail:"",version:"grokbot-tunnel v9.9.9 (test)",email:"",label:"ha"}' \
  > "${GROKBOT_STATE_DIR}/status.json"

"${httpd[@]}" -f -p "127.0.0.1:${port}" -h "${work}/www" -c "$conf" &
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

grep -q '^A:172.30.32.2$' "$conf" || fail "ingress address is not allowed"
grep -q '^A:127.0.0.1$' "$conf" || fail "health check address is not allowed"
grep -q '^D:\*$' "$conf" || fail "other addresses are not denied"

page=$(curl -fsS "http://127.0.0.1:${port}/")
grep -q "Grok Bot client" <<<"$page" || fail "page title missing"
grep -q 'id="signout"[^>]*hidden' <<<"$page" || fail "Sign out starts visible"
grep -q 'id="permission"' <<<"$page" || fail "permission choice missing"
if grep -q 'id="permission"[^>]*hidden' <<<"$page"; then
  fail "permission choice starts hidden"
fi
grep -q 'Always allow' <<<"$page" || fail "Always allow missing"
grep -q 'Ask every time' <<<"$page" || fail "Ask every time missing"
grep -q 'Never allow' <<<"$page" || fail "Never allow missing"
if grep -q 'checked' <<<"$page"; then
  fail "a permission starts selected"
fi
grep -q 'Click to sign in' <<<"$page" || fail "sign-in link missing"
grep -q 'id="link-row"[^>]*hidden' <<<"$page" || fail "link row starts visible"
grep -q 'aria-label="Copy"' <<<"$page" || fail "copy icon missing"
buttons=$(grep -c '<button' <<<"$page")
[[ "$buttons" == "2" ]] || fail "expected two buttons, found ${buttons}"
css=$(curl -fsS "http://127.0.0.1:${port}/style.css")
grep -q '\[hidden\]' <<<"$css" || fail "hidden rule missing"
grep -q 'display: none !important' <<<"$css" || fail "hidden does not override display"
grep -q 'prefers-color-scheme: dark' <<<"$css" || fail "dark scheme missing"
js=$(curl -fsS "http://127.0.0.1:${port}/app.js")
grep -q 'show(signout, connected)' <<<"$js" || fail "Sign out is not limited to connected"
grep -q 'show(permission, !connected)' <<<"$js" || fail "permission choice is not shown before sign-in"
grep -q 'cgi-bin/permission' <<<"$js" || fail "permission URL missing"
grep -q 'addEventListener("error"' <<<"$js" || fail "QR load is not retried"
grep -q 'cgi-bin/status' <<<"$js" || fail "status URL missing"
grep -q 'cgi-bin/sign-out' <<<"$js" || fail "sign-out URL missing"
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
python3 -c 'import os; p=os.environ["GROKBOT_STATE_DIR"]+"/qr.svg"; open(p,"w").write("<svg xmlns=\"http://www.w3.org/2000/svg\">"+"x"*70000+"</svg>\n")'
size=$(wc -c < "${GROKBOT_STATE_DIR}/qr.svg" | tr -d '[:space:]')
served=$(curl -fsS -o "${work}/qr-big.svg" -w '%{size_download}' "http://127.0.0.1:${port}/qr.svg")
[[ "$size" -gt 65536 ]] || fail "fixture was not larger than 64 KiB"
[[ "$served" == "$size" ]] || fail "large qr truncated ${served} != ${size}"
grep -q '</svg>' "${work}/qr-big.svg" || fail "large qr was cut off"

status=$(curl -fsS "http://127.0.0.1:${port}/cgi-bin/status")
[[ "$(jq -r '.status' <<<"$status")" == "Waiting for sign-in" ]] || fail "status payload"
[[ "$(jq -r '.login_url' <<<"$status")" == https://example.test/* ]] || fail "status url"
[[ "$(jq -r '.permission' <<<"$status")" == "" ]] || fail "unset permission was $(jq -r '.permission' <<<"$status")"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST --data 'ask' "http://127.0.0.1:${port}/cgi-bin/permission")
[[ "$code" == "403" ]] || fail "permission without the panel header was ${code}"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "X-Grokbot-Panel: 1" --data 'nope' \
  "http://127.0.0.1:${port}/cgi-bin/permission")
[[ "$code" == "400" ]] || fail "bad permission was ${code}"
[[ ! -e "$GROKBOT_PERMISSION_FILE" ]] || fail "bad permission was saved"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "X-Grokbot-Panel: 1" --data 'ask' \
  "http://127.0.0.1:${port}/cgi-bin/permission")
[[ "$code" == "204" ]] || fail "permission returned ${code}"
[[ "$(tr -d '[:space:]' < "$GROKBOT_PERMISSION_FILE")" == "ask" ]] || fail "permission file"
status=$(curl -fsS "http://127.0.0.1:${port}/cgi-bin/status")
[[ "$(jq -r '.permission' <<<"$status")" == "ask" ]] || fail "status permission"
rm -f "${GROKBOT_STATE_DIR}/status.json"
status=$(curl -fsS "http://127.0.0.1:${port}/cgi-bin/status")
[[ "$(jq -r '.state' <<<"$status")" == "starting" ]] || fail "missing status file"

code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:${port}/cgi-bin/sign-out")
[[ "$code" == "403" ]] || fail "missing panel header was ${code}"
printf '%s\n' '{"refresh_token":"secret"}' > "${GROKBOT_STORE}/auth.json"
printf '%s\n' '{"credential":"secret"}' > "${GROKBOT_STORE}/computer.json"
printf '%s\n' '{"machine_id":"keep-me"}' > "${GROKBOT_STORE}/machine.json"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H "X-Grokbot-Panel: 1" \
  "http://127.0.0.1:${port}/cgi-bin/sign-out")
[[ "$code" == "204" ]] || fail "sign-out returned ${code}"
[[ ! -e "${GROKBOT_STORE}/auth.json" ]] || fail "auth.json survived sign-out"
[[ ! -e "${GROKBOT_STORE}/computer.json" ]] || fail "computer.json survived sign-out"
[[ -f "${GROKBOT_STORE}/machine.json" ]] || fail "machine.json was removed"
[[ ! -e "${GROKBOT_STATE_DIR}/control" ]] || fail "sign-out still writes a control file"

code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${port}/../etc/passwd")
[[ "$code" == "404" || "$code" == "400" ]] || fail "path traversal returned ${code}"

printf '%s\n' "panel tests passed"
