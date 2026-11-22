#!/usr/bin/env bash
# Updater: checksum success, checksum failure, and keeping the last binary.
set -euo pipefail

root="$(cd "$(dirname -- "$0")/.." && pwd)"
# shellcheck source=../grokbot_client/rootfs/usr/lib/grokbot/common.sh
source "${root}/grokbot_client/rootfs/usr/lib/grokbot/common.sh"

work=$(mktemp -d)
server_pid=""
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

arch=$(grok_tunnel_arch)
releases="${work}/releases"
mkdir -p "$releases"
payload="${work}/payload"
mkdir -p "$payload"
cat > "${payload}/grokbot-tunnel-linux-${arch}" <<'EOF'
#!/bin/sh
printf '%s\n' "grokbot-tunnel v9.9.9 (test)"
exit 0
EOF
chmod 0755 "${payload}/grokbot-tunnel-linux-${arch}"
archive="grokbot-tunnel-linux-${arch}.tar.gz"
tar -czf "${releases}/${archive}" -C "$payload" "grokbot-tunnel-linux-${arch}"
sha256sum "${releases}/${archive}" | awk -v name="$archive" '{ print $1 "  " name }' > "${releases}/checksums.txt"

python3 "${root}/tests/release_server.py" --root "$releases" > "${work}/port" &
server_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if [[ -s "${work}/port" ]]; then
    break
  fi
  sleep 0.1
done
port=$(cat "${work}/port")
export GROKBOT_TUNNEL_RELEASES_URL="http://127.0.0.1:${port}"
export GROKBOT_BIN="${work}/bin/grokbot-tunnel"
export GROKBOT_STATE_DIR="${work}/run"
mkdir -p "${work}/bin" "$GROKBOT_STATE_DIR"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

grok_ensure_binary true
[[ -x "$GROKBOT_BIN" ]] || fail "binary was not installed"
got=$("$GROKBOT_BIN" --version)
[[ "$got" == "grokbot-tunnel v9.9.9 (test)" ]] || fail "unexpected version: $got"

# Same version is left in place even if the archive disappears.
rm -f "${releases}/${archive}"
grok_ensure_binary true
[[ "$("$GROKBOT_BIN" --version)" == "grokbot-tunnel v9.9.9 (test)" ]] || fail "missing archive replaced a current client"

# An older binary is kept when the new archive fails the checksum.
cat > "$GROKBOT_BIN" <<'EOF'
#!/bin/sh
printf '%s\n' "grokbot-tunnel v1.0.0 (test)"
exit 0
EOF
chmod 0755 "$GROKBOT_BIN"
tar -czf "${releases}/${archive}" -C "$payload" "grokbot-tunnel-linux-${arch}"
printf '%s\n' "0000000000000000000000000000000000000000000000000000000000000000  ${archive}" > "${releases}/checksums.txt"
grok_ensure_binary true
[[ "$("$GROKBOT_BIN" --version)" == "grokbot-tunnel v1.0.0 (test)" ]] || fail "bad checksum replaced the working client"

# With no working client, a bad checksum does not install anything.
rm -f "$GROKBOT_BIN"
if grok_ensure_binary true; then
  fail "bad checksum installed a client from nothing"
fi
[[ ! -e "$GROKBOT_BIN" ]] || fail "bad checksum left a binary behind"

# No published checksum, and no client yet: install and say so.
rm -f "${releases}/checksums.txt"
log="${work}/nocheck.log"
if ! grok_ensure_binary true >"$log" 2>&1; then
  fail "install without checksums.txt failed"
fi
grep -q "without a checksum" "$log" || fail "missing checksum was not reported"
[[ "$("$GROKBOT_BIN" --version)" == "grokbot-tunnel v9.9.9 (test)" ]] || fail "unverified first install did not run"

# A newer release that cannot be downloaded leaves the working client in place.
cat > "$GROKBOT_BIN" <<'EOF'
#!/bin/sh
printf '%s\n' "grokbot-tunnel v1.0.0 (test)"
exit 0
EOF
chmod 0755 "$GROKBOT_BIN"
rm -f "${releases}/${archive}"
grok_ensure_binary true
[[ "$("$GROKBOT_BIN" --version)" == "grokbot-tunnel v1.0.0 (test)" ]] || fail "failed download replaced the working client"
cat > "$GROKBOT_BIN" <<'EOF'
#!/bin/sh
printf '%s\n' "grokbot-tunnel v9.9.9 (test)"
exit 0
EOF
chmod 0755 "$GROKBOT_BIN"

# auto_update false does not replace a client, and does not need the network.
export GROKBOT_TUNNEL_RELEASES_URL="http://127.0.0.1:1"
grok_ensure_binary false
[[ "$("$GROKBOT_BIN" --version)" == "grokbot-tunnel v9.9.9 (test)" ]] || fail "auto_update false changed the client"

printf '%s\n' "update tests passed"
