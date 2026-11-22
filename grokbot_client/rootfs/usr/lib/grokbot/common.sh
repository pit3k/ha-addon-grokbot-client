# Shared helpers for the Grok Bot client service.
# Secrets live in ${HOME}/.grok/bot-tunnel. These helpers never print that
# directory's token fields. The sign-in URL is not a token; the service logs
# it once so it can be opened from the app log if the panel is unavailable.

# shellcheck shell=bash

: "${GROKBOT_BIN:=/data/.local/bin/grokbot-tunnel}"
: "${GROKBOT_STATE_DIR:=/run/grokbot}"
: "${GROKBOT_OPTIONS_FILE:=/data/options.json}"

grok_store_dir() {
  printf '%s\n' "${GROKBOT_STORE:-${HOME}/.grok/bot-tunnel}"
}

grok_log() {
  local level="$1"
  shift
  # The s6 run file is interpreted by bashio, then execs this script in a new
  # shell. The bashio:: functions are not loaded here. A command named bashio
  # existing on PATH is not enough: calling bashio::log would print
  # "command not found" and drop the sign-in link.
  if declare -F bashio::log.info >/dev/null 2>&1; then
    case "$level" in
      warning) bashio::log.warning "$*" ;;
      error) bashio::log.error "$*" ;;
      *) bashio::log.info "$*" ;;
    esac
    return 0
  fi
  printf '%s\n' "$*" >&2
}

grok_tunnel_arch() {
  case "$(uname -m)" in
    x86_64 | amd64) printf '%s\n' amd64 ;;
    aarch64 | arm64) printf '%s\n' arm64 ;;
    *) return 1 ;;
  esac
}

grok_option() {
  local key="$1"
  local default="$2"
  local value="$default"
  if [[ -f "$GROKBOT_OPTIONS_FILE" ]]; then
    value=$(jq -r --arg k "$key" --arg d "$default" '
      if has($k) and .[$k] != null then
        if (.[$k] | type) == "string" then .[$k]
        else (.[$k] | tostring)
        end
      else $d end
    ' "$GROKBOT_OPTIONS_FILE" 2>/dev/null) || value="$default"
  fi
  printf '%s\n' "$value"
}

grok_normalize_permission() {
  case "$1" in
    always | ask) printf '%s\n' "$1" ;;
    *)
      grok_log warning "Permission '${1}' is not always or ask. Using always."
      printf '%s\n' always
      ;;
  esac
}

grok_normalize_label() {
  local label="$1"
  label=${label//$'\n'/}
  label=${label//$'\r'/}
  label=${label#"${label%%[![:space:]]*}"}
  label=${label%"${label##*[![:space:]]}"}
  if [[ -z "$label" ]]; then
    label="ha"
  fi
  printf '%s\n' "${label:0:100}"
}

grok_installed_version() {
  local line=""
  if [[ -x "$GROKBOT_BIN" ]]; then
    line=$("$GROKBOT_BIN" --version 2>/dev/null | head -n 1 || true)
  fi
  if [[ -z "$line" ]]; then
    printf '%s\n' "not installed"
  else
    printf '%s\n' "$line"
  fi
}

grok_bin_release() {
  local line=""
  line=$(grok_installed_version)
  if [[ "$line" == "not installed" ]]; then
    return 1
  fi
  printf '%s\n' "$line" | awk '{print $2}'
}

grok_logged_in() {
  local auth
  auth="$(grok_store_dir)/auth.json"
  [[ -f "$auth" ]] || return 1
  jq -e '(try .refresh_token catch "") | type == "string" and length > 0' "$auth" >/dev/null 2>&1
}

grok_account_email() {
  local auth email=""
  auth="$(grok_store_dir)/auth.json"
  [[ -f "$auth" ]] || return 0
  email=$(jq -r 'if (.email | type) == "string" then .email else "" end' "$auth" 2>/dev/null || true)
  email=${email//$'\n'/}
  email=${email//$'\r'/}
  printf '%s\n' "${email:0:200}"
}

grok_wipe_login() {
  local store
  store="$(grok_store_dir)"
  rm -f "${store}/auth.json" "${store}/computer.json"
  rm -f "${GROKBOT_STATE_DIR}/notified_url" "${GROKBOT_STATE_DIR}/notify_warned" \
    "${GROKBOT_STATE_DIR}/qr.svg"
}

# Drop secret lines. BusyBox sed rejects the GNU /I flag, so this uses grep -i.
grok_redact_text() {
  grep -viE 'refresh_token|access_token|authorization:[[:space:]]*bearer|eyJ[A-Za-z0-9_-]{8,}[.][A-Za-z0-9_-]{8,}' \
    | tr '\n' ' ' \
    | cut -c1-500 || true
}

grok_write_qr() {
  local url="$1"
  local out="${GROKBOT_STATE_DIR}/qr.svg"
  command -v qrencode >/dev/null 2>&1 || return 0
  qrencode -t SVG -o "$out" -m 2 "$url" || rm -f "$out"
}

# A Sign in click while a session exists must not stop the tunnel.
# Returns 0 after discarding that request.
grok_signin_is_harmless() {
  local file="${GROKBOT_STATE_DIR}/control"
  local cmd=""
  [[ -s "$file" ]] || return 1
  cmd=$(tr -d '[:space:]' <"$file" || true)
  [[ "$cmd" == "sign-in" ]] || return 1
  grok_logged_in || return 1
  rm -f "$file"
  grok_log info "Sign in ignored; already signed in."
  return 0
}

grok_tail_error() {
  local file="$1"
  local text=""
  [[ -f "$file" ]] || return 0
  text=$(grok_redact_text <"$file" || true)
  text=${text#"${text%%[![:space:]]*}"}
  text=${text%"${text##*[![:space:]]}"}
  printf '%s\n' "$text"
}

grok_extract_url() {
  local file="$1"
  local url=""
  [[ -f "$file" ]] || return 1
  url=$(grep -oE 'https://[^[:space:]<>"'"'"']+' "$file" 2>/dev/null | head -n 1 || true)
  [[ "$url" == https://* ]] || return 1
  printf '%s\n' "$url"
}

grok_write_status() {
  local state="$1"
  local status="$2"
  local url="$3"
  local error="$4"
  local version="$5"
  local email="$6"
  local label="$7"
  local detail="${8:-}"
  local tmp
  mkdir -p "$GROKBOT_STATE_DIR"
  tmp=$(mktemp "${GROKBOT_STATE_DIR}/status.XXXXXX")
  if ! jq -n \
    --arg state "$state" \
    --arg status "$status" \
    --arg login_url "$url" \
    --arg error "$error" \
    --arg detail "$detail" \
    --arg version "$version" \
    --arg email "$email" \
    --arg label "$label" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{state:$state,status:$status,login_url:$login_url,error:$error,detail:$detail,version:$version,email:$email,label:$label,updated:$updated}' \
    >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chmod 644 "$tmp"
  mv -f "$tmp" "${GROKBOT_STATE_DIR}/status.json"
}

grok_take_control() {
  local file="${GROKBOT_STATE_DIR}/control"
  local cmd=""
  # An empty file is a writer that has not finished. Leave it for the next check.
  [[ -s "$file" ]] || return 1
  cmd=$(tr -d '[:space:]' <"$file" || true)
  case "$cmd" in
    sign-in | sign-out)
      rm -f "$file"
      printf '%s\n' "$cmd"
      return 0
      ;;
  esac
  rm -f "$file"
  return 1
}

grok_download() {
  local url="$1"
  local dest="$2"
  curl -fsSL --retry 3 --retry-delay 2 --max-time 120 -o "$dest" "$url"
}

grok_latest_version() {
  local base url version
  base="${GROKBOT_TUNNEL_RELEASES_URL:-https://github.com/exa-pub/grokbot-tunnel}"
  base="${base%/}"
  url=$(curl -fsSL --retry 3 --retry-delay 2 --max-time 30 -o /dev/null -w '%{url_effective}' "${base}/releases/latest") || return 1
  version="${url##*/}"
  [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] || return 1
  printf '%s\n' "$version"
}

grok_verify_checksum() {
  local sums="$1"
  local file="$2"
  local name="$3"
  local expected="" actual=""
  expected=$(awk -v f="$name" '$2 == f { print $1; exit }' "$sums")
  if [[ ! "$expected" =~ ^[a-fA-F0-9]{64}$ ]]; then
    return 2
  fi
  actual=$(sha256sum "$file" | awk '{ print $1 }')
  [[ "${actual,,}" == "${expected,,}" ]]
}

grok_keep_or_fail() {
  local message="$1"
  if [[ -x "$GROKBOT_BIN" ]]; then
    grok_log warning "${message}. Keeping the installed client."
    return 0
  fi
  grok_log error "${message}, and no client is installed."
  return 1
}

# Download latest (or install the first copy) into GROKBOT_BIN.
# auto_update "true" replaces an older release. Any other value keeps the
# current binary and only downloads when it is missing.
# A failed download or a bad checksum leaves the previous binary in place.
grok_ensure_binary() {
  local auto_update="${1:-true}"
  local arch="" version="" installed="" base="" archive="" tmp="" extracted="" rc=0
  local sums_rc=0
  arch=$(grok_tunnel_arch) || {
    grok_log error "Unsupported architecture $(uname -m)."
    return 1
  }
  mkdir -p "$(dirname "$GROKBOT_BIN")"

  if [[ -x "$GROKBOT_BIN" && "$auto_update" != "true" ]]; then
    return 0
  fi

  if ! version=$(grok_latest_version); then
    grok_keep_or_fail "Could not look up the latest grokbot-tunnel release"
    return $?
  fi

  if [[ -x "$GROKBOT_BIN" ]]; then
    installed=$(grok_bin_release || true)
  fi
  if [[ -n "$installed" && "$installed" == "$version" ]]; then
    return 0
  fi

  base="${GROKBOT_TUNNEL_RELEASES_URL:-https://github.com/exa-pub/grokbot-tunnel}"
  base="${base%/}"
  archive="grokbot-tunnel-linux-${arch}.tar.gz"
  tmp=$(mktemp -d)
  grok_log info "Downloading grokbot-tunnel ${version} (linux/${arch})"

  if ! grok_download "${base}/releases/download/${version}/${archive}" "${tmp}/${archive}"; then
    rm -rf "$tmp"
    grok_keep_or_fail "Download of grokbot-tunnel ${version} failed"
    return $?
  fi

  if grok_download "${base}/releases/download/${version}/checksums.txt" "${tmp}/checksums.txt"; then
    sums_rc=0
    grok_verify_checksum "${tmp}/checksums.txt" "${tmp}/${archive}" "$archive" || sums_rc=$?
    if [[ "$sums_rc" -eq 1 ]]; then
      rm -rf "$tmp"
      grok_keep_or_fail "Checksum mismatch for ${archive}"
      return $?
    fi
    if [[ "$sums_rc" -eq 2 ]]; then
      if [[ -x "$GROKBOT_BIN" ]]; then
        rm -rf "$tmp"
        grok_log warning "checksums.txt has no entry for ${archive}. Keeping the installed client."
        return 0
      fi
      grok_log warning "checksums.txt has no entry for ${archive}. Installing ${version} without a checksum."
    else
      grok_log info "Checksum verified for ${archive}"
    fi
  else
    if [[ -x "$GROKBOT_BIN" ]]; then
      rm -rf "$tmp"
      grok_log warning "checksums.txt is not published for ${version}. Keeping the installed client."
      return 0
    fi
    grok_log warning "checksums.txt is not published for ${version}. Installing without a checksum."
  fi

  if ! tar -xzf "${tmp}/${archive}" -C "$tmp"; then
    rm -rf "$tmp"
    grok_keep_or_fail "Could not unpack ${archive}"
    return $?
  fi

  extracted=""
  while IFS= read -r candidate; do
    extracted="$candidate"
    break
  done < <(find "$tmp" -type f -name "grokbot-tunnel-linux-${arch}")
  if [[ -z "$extracted" ]]; then
    rm -rf "$tmp"
    grok_keep_or_fail "Archive does not contain grokbot-tunnel-linux-${arch}"
    return $?
  fi

  install -m 0755 "$extracted" "${tmp}/grokbot-tunnel.new"
  if ! "${tmp}/grokbot-tunnel.new" --version >/dev/null 2>&1; then
    rm -rf "$tmp"
    grok_keep_or_fail "Downloaded grokbot-tunnel does not run on this system"
    return $?
  fi

  if [[ -x "$GROKBOT_BIN" ]]; then
    cp -a "$GROKBOT_BIN" "${GROKBOT_BIN}.prev" || rc=1
  fi
  if [[ "$rc" -eq 0 ]]; then
    mv -f "${tmp}/grokbot-tunnel.new" "$GROKBOT_BIN" || rc=1
  fi
  rm -rf "$tmp"
  if [[ "$rc" -ne 0 ]]; then
    if [[ -x "${GROKBOT_BIN}.prev" && ! -x "$GROKBOT_BIN" ]]; then
      mv -f "${GROKBOT_BIN}.prev" "$GROKBOT_BIN" || true
    fi
    grok_keep_or_fail "Could not replace the grokbot-tunnel binary"
    return $?
  fi
  if ! "$GROKBOT_BIN" --version >/dev/null 2>&1; then
    if [[ -x "${GROKBOT_BIN}.prev" ]]; then
      mv -f "${GROKBOT_BIN}.prev" "$GROKBOT_BIN"
      grok_log error "The new client does not run. Restored the previous one."
      return 0
    fi
    grok_log error "The installed client does not run."
    return 1
  fi
  grok_log info "Installed $(grok_installed_version) at ${GROKBOT_BIN}"
  return 0
}

grok_notify() {
  local url="$1"
  local now last body stamp
  [[ -n "${SUPERVISOR_TOKEN:-}" ]] || return 0
  stamp="${GROKBOT_STATE_DIR}/notified_url"
  if [[ -f "$stamp" ]] && [[ "$(cat "$stamp")" == "$url" ]]; then
    return 0
  fi
  now=$(date +%s)
  last=0
  if [[ -f "${GROKBOT_STATE_DIR}/notify_try" ]]; then
    last=$(cat "${GROKBOT_STATE_DIR}/notify_try" || echo 0)
  fi
  if [[ "$last" =~ ^[0-9]+$ ]] && ((now - last < 15)); then
    return 0
  fi
  printf '%s\n' "$now" >"${GROKBOT_STATE_DIR}/notify_try"
  body=$(jq -n --arg url "$url" '{
    title: "Grok Bot client",
    notification_id: "grokbot_client_signin",
    message: ("Sign in to connect this Home Assistant system to Grok Bot.\n\n" + $url + "\n\nYou can also open Grok Bot client in the sidebar.")
  }') || return 1
  if curl -fsS --max-time 10 -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "http://supervisor/core/api/services/persistent_notification/create" >/dev/null; then
    printf '%s\n' "$url" >"$stamp"
    rm -f "${GROKBOT_STATE_DIR}/notify_warned"
    return 0
  fi
  if [[ ! -f "${GROKBOT_STATE_DIR}/notify_warned" ]]; then
    grok_log warning "Home Assistant is not ready for the sign-in notification yet. The panel still shows the link."
    : >"${GROKBOT_STATE_DIR}/notify_warned"
  fi
  return 1
}

grok_dismiss_notification() {
  [[ -n "${SUPERVISOR_TOKEN:-}" ]] || return 0
  rm -f "${GROKBOT_STATE_DIR}/notified_url"
  curl -fsS --max-time 10 -X POST \
    -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"notification_id":"grokbot_client_signin"}' \
    "http://supervisor/core/api/services/persistent_notification/dismiss" >/dev/null || true
}

# Stop pid and the commands it started. Children go first so a shell waiting
# on sleep does not leave that sleep behind, then the process itself.
# Only the kernel's children list (or ps --ppid) is used, never a scan that
# could mistake an unrelated process for a child.
grok_kill_pid_tree() {
  local pid="$1"
  local signal="$2"
  local child
  local -a kids=()
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  ((pid > 1)) || return 0
  if [[ "$pid" == "$$" || "$pid" == "${PPID:-}" ]]; then
    return 0
  fi
  if [[ -r "/proc/${pid}/task/${pid}/children" ]]; then
    # The file often has no trailing newline, so read returns non-zero.
    read -r -a kids <"/proc/${pid}/task/${pid}/children" || true
  else
    mapfile -t kids < <(ps -o pid= --ppid "$pid" 2>/dev/null || true)
  fi
  for child in "${kids[@]}"; do
    grok_kill_pid_tree "$child" "$signal"
  done
  kill "-${signal}" "$pid" 2>/dev/null || true
}

grok_kill_child() {
  local pid="${GROKBOT_CHILD:-0}"
  local i
  if [[ "$pid" == "0" && -f "${GROKBOT_STATE_DIR}/child.pid" ]]; then
    pid=$(cat "${GROKBOT_STATE_DIR}/child.pid" || true)
  fi
  # pid 0 means "this process group" to kill(2). Never signal it.
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    grok_kill_pid_tree "$pid" TERM
    for i in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$pid" 2>/dev/null; then
      grok_kill_pid_tree "$pid" KILL
    fi
  fi
  wait "$pid" 2>/dev/null || true
  GROKBOT_CHILD=0
  rm -f "${GROKBOT_STATE_DIR}/child.pid"
}

grok_spawn_redirect() {
  local out="$1"
  local err="$2"
  shift 2
  "$@" >"$out" 2>"$err" &
  GROKBOT_CHILD=$!
  printf '%s\n' "$GROKBOT_CHILD" >"${GROKBOT_STATE_DIR}/child.pid"
}

grok_sleep() {
  local seconds="$1"
  local i
  for ((i = 0; i < seconds; i++)); do
    if grok_signin_is_harmless; then
      sleep 1
      continue
    fi
    if [[ -s "${GROKBOT_STATE_DIR}/control" ]]; then
      return 1
    fi
    sleep 1
  done
  return 0
}

grok_next_backoff() {
  local n="$1"
  if ((n < 60)); then
    n=$((n * 2))
  fi
  if ((n > 60)); then
    n=60
  fi
  printf '%s\n' "$n"
}
