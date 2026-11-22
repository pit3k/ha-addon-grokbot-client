#!/bin/bash
# Run grokbot-tunnel. s6 owns this process. Sign-out stops it and starts it again.
set -euo pipefail

ensure() {
  local a n f ver tmp base
  bin=${GROKBOT_BIN:-/data/.local/bin/grokbot-tunnel}
  case $(uname -m) in
    x86_64|amd64) a=amd64 ;;
    aarch64|arm64) a=arm64 ;;
    *) printf '%s\n' "Unsupported architecture $(uname -m)" >&2; return 1 ;;
  esac
  [ -x "$bin" ] && [ "${1:-true}" != true ] && return 0
  base=${GROKBOT_TUNNEL_RELEASES_URL:-https://github.com/exa-pub/grokbot-tunnel}
  ver=$(curl -fsSL --retry 3 --retry-delay 2 --max-time 30 -o /dev/null -w '%{url_effective}' "$base/releases/latest") || { [ -x "$bin" ]; return; }
  ver=${ver##*/}
  [[ "$ver" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]] || { [ -x "$bin" ]; return; }
  [ -x "$bin" ] && [ "$("$bin" --version 2>/dev/null | awk '{print $2}' || true)" = "$ver" ] && return 0
  tmp=$(mktemp -d); n="grokbot-tunnel-linux-${a}"; f="${n}.tar.gz"
  curl -fsSL --retry 3 --retry-delay 2 --max-time 120 -o "$tmp/$f" "$base/releases/download/$ver/$f" || { rm -rf "$tmp"; [ -x "$bin" ]; return; }
  if curl -fsSL --retry 3 --max-time 30 -o "$tmp/checksums.txt" "$base/releases/download/$ver/checksums.txt"; then
    awk -v f="$f" '$2 == f { print $1 "  " $2 }' "$tmp/checksums.txt" | (cd "$tmp" && sha256sum -c - >/dev/null) || { rm -rf "$tmp"; [ -x "$bin" ]; return; }
  fi
  tar -xzf "$tmp/$f" -C "$tmp" && "$tmp/$n" --version >/dev/null 2>&1 && install -m 0755 "$tmp/$n" "$bin" || true
  rm -rf "$tmp"; [ -x "$bin" ]
}

signed() { jq -e '(.refresh_token|type)=="string" and (.refresh_token|length)>0' "$store/auth.json" >/dev/null 2>&1; }

# The sign-in page writes this. Empty means the page saved nothing.
chosen() {
  local p f=${GROKBOT_PERMISSION_FILE:-$HOME/permission}
  p=$( [ -f "$f" ] && tr -d '[:space:]' <"$f" || true )
  case $p in always|ask|never) printf '%s\n' "$p" ;; esac
}

show_link() {
  [ -n "$url" ] && return 0
  url=$(grep -oE 'https://[^[:space:]<>"'"'"']+' "$out" | head -n 1 || true)
  [ -n "$url" ] || return 0
  printf '%s\n' "Sign-in link: ${url}"
  qrencode -t SVG -o "$state/qr.svg" -m 2 "$url" || true
  jq -n --arg u "$url" --arg l "$label" '{state:"waiting",status:"Waiting for sign-in",login_url:$u,error:"",detail:"",version:"",email:"",label:$l}' >"$state/status.json"
}

main() {
  export HOME="${GROKBOT_HOME:-/data}"
  export GROKBOT_BIN="${GROKBOT_BIN:-$HOME/.local/bin/grokbot-tunnel}"
  bin=$GROKBOT_BIN
  store=${GROKBOT_STORE:-$HOME/.grok/bot-tunnel}
  state=${GROKBOT_STATE_DIR:-/run/grokbot}
  opt=${GROKBOT_OPTIONS_FILE:-/data/options.json}
  mkdir -p "$(dirname "$bin")" "$store" "$state"
  chmod 700 "$store" || true
  label=$(jq -r '.label' "$opt"); level=$(jq -r '.log_level' "$opt"); first=0
  ensure "$(jq -r '.auto_update' "$opt")" || exit 1
  if ! signed; then
    first=1
    out=$state/login.out; : >"$out"; url=""; pid=0
    # s6 signals this script. Forward that to login; after exec, s6 signals the client itself.
    trap 'if [ "$pid" -ne 0 ]; then kill "$pid" 2>/dev/null || true; fi; exit 0' TERM INT
    "$bin" login --no-browser >"$out" 2>&1 & pid=$!
    while kill -0 "$pid" 2>/dev/null; do show_link; sleep 1; done
    wait "$pid" || true
    show_link
    signed || exit 1
  fi
  rm -f "$state/qr.svg"
  email=$(jq -r 'if (.email|type)=="string" then .email else "" end' "$store/auth.json" 2>/dev/null || true)
  jq -n --arg l "$label" --arg e "$email" '{state:"connected",status:("Connected as "+$l),login_url:"",error:"",detail:"",version:"",email:$e,label:$l}' >"$state/status.json"
  set -- connect --label "$label" --root /
  # A saved choice is sent once, on the connect that follows sign-in.
  if [ "$first" = 1 ]; then
    perm=$(chosen)
    if [ -n "$perm" ]; then
      set -- "$@" --permission "$perm"
    fi
  fi
  if [ "$level" = debug ]; then
    set -- "$@" --debug
  fi
  exec "$bin" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
