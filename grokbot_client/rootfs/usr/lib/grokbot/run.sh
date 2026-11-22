#!/usr/bin/env bash
# Supervise grokbot-tunnel. s6 restarts this script if it exits; the script
# itself restarts login and connect so the panel stays responsive.
# shellcheck shell=bash

set -uo pipefail

# shellcheck source=common.sh
source "${GROKBOT_COMMON:-/usr/lib/grokbot/common.sh}"

grok_run_login() {
  local label="$1"
  local out="${GROKBOT_STATE_DIR}/login.out"
  local err="${GROKBOT_STATE_DIR}/login.err"
  local url="" pid rc=0 error="" version
  version=$(grok_installed_version)
  : >"$out"
  : >"$err"
  export GROKBOT_LOG_OFFSET=0
  chmod 600 "$out" "$err" || true
  grok_write_status "waiting" "Waiting for sign-in" "" "" "$version" "" "$label" "Preparing the sign-in link…"
  grok_spawn_redirect "$out" "$err" "$GROKBOT_BIN" login --no-browser
  pid="$GROKBOT_CHILD"
  while kill -0 "$pid" 2>/dev/null; do
    grok_forward_log "$err"
    if grok_signin_is_harmless; then
      continue
    fi
    if [[ -s "${GROKBOT_STATE_DIR}/control" ]]; then
      grok_kill_child
      return 10
    fi
    if [[ -z "$url" ]]; then
      url=$(grok_extract_url "$out" || true)
      if [[ -z "$url" ]]; then
        url=$(grok_extract_url "$err" || true)
      fi
      if [[ -n "$url" ]]; then
        grok_log info "Sign-in link: ${url}"
        grok_write_qr "$url"
        grok_write_status "waiting" "Waiting for sign-in" "$url" "" "$version" "" "$label" ""
        grok_notify "$url" || true
      fi
    else
      grok_notify "$url" || true
    fi
    sleep 1
  done
  wait "$pid" || rc=$?
  grok_forward_log "$err"
  GROKBOT_CHILD=0
  rm -f "${GROKBOT_STATE_DIR}/child.pid"
  if grok_logged_in; then
    grok_dismiss_notification || true
    return 0
  fi
  error=$(grok_tail_error "$err")
  if [[ -z "$error" ]]; then
    error=$(grok_tail_error "$out")
  fi
  if [[ -z "$error" ]]; then
    error="Sign-in did not finish (exit ${rc}). A new link will be prepared."
    grok_log error "$error"
  elif ! grok_forwards_client_log; then
    grok_log error "$error"
  fi
  grok_write_status "signed_out" "Not signed in" "" "$error" "$version" "" "$label" ""
  return 1
}

grok_run_connect() {
  local permission="$1"
  local label="$2"
  local err="${GROKBOT_STATE_DIR}/connect.err"
  local version email started rc=0
  local debug=()
  version=$(grok_installed_version)
  email=$(grok_account_email)
  : >"$err"
  export GROKBOT_LOG_OFFSET=0
  chmod 600 "$err" || true
  grok_write_status "connected" "Connected as ${label}" "" "" "$version" "$email" "$label" ""
  rm -f "${GROKBOT_STATE_DIR}/qr.svg"
  grok_dismiss_notification || true
  grok_log info "Connecting as ${label} with permission ${permission}."
  started=$SECONDS
  if [[ "$(grok_normalize_log_level "$(grok_option log_level info)")" == "debug" ]]; then
    debug=(--debug)
  fi
  grok_spawn_redirect /dev/null "$err" "$GROKBOT_BIN" connect \
    --permission "$permission" \
    --label "$label" \
    --root / \
    "${debug[@]}"
  grok_wait_child "$err" || rc=$?
  GROKBOT_LAST_RUN_SECONDS=$((SECONDS - started))
  return "$rc"
}

grok_wait_child() {
  local err="$1"
  local pid="$GROKBOT_CHILD"
  local rc=0
  while kill -0 "$pid" 2>/dev/null; do
    grok_forward_log "$err"
    if grok_signin_is_harmless; then
      continue
    fi
    if [[ -s "${GROKBOT_STATE_DIR}/control" ]]; then
      grok_kill_child
      return 10
    fi
    sleep 1
  done
  wait "$pid" || rc=$?
  grok_forward_log "$err"
  GROKBOT_CHILD=0
  rm -f "${GROKBOT_STATE_DIR}/child.pid"
  return "$rc"
}

grok_main() {
  local backoff=2
  export HOME="${GROKBOT_HOME:-/data}"
  export SHELL="${SHELL:-/bin/bash}"
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  export GROKBOT_BIN="${GROKBOT_BIN:-${HOME}/.local/bin/grokbot-tunnel}"
  mkdir -p "$GROKBOT_STATE_DIR" "$(dirname "$GROKBOT_BIN")" "$(grok_store_dir)"
  chmod 700 "$(grok_store_dir)" || true

  trap 'grok_kill_child; exit 0' TERM INT

  grok_log info "Grok Bot client starting. Home is ${HOME}."

  while true; do
    local permission="" label="" auto_update="" cmd="" version="" rc=0 error=""
    permission=$(grok_normalize_permission "$(grok_option permission always)")
    label=$(grok_normalize_label "$(grok_option label homeassistant)")
    auto_update=$(grok_option auto_update true)

    if cmd=$(grok_take_control); then
      grok_log info "Panel requested ${cmd}."
      if [[ "$cmd" == "sign-out" ]]; then
        grok_kill_child
        grok_write_status "signed_out" "Not signed in" "" "" "$(grok_installed_version)" "" "$label" ""
        grok_wipe_login
        grok_dismiss_notification || true
      elif grok_logged_in; then
        grok_log info "Sign in ignored; already signed in."
      else
        grok_kill_child
      fi
    fi

    if ! grok_ensure_binary "$auto_update"; then
      grok_write_status "signed_out" "Not signed in" "" \
        "Could not download the Grok Bot client. Retrying." \
        "not installed" "" "$label" ""
      if ! grok_sleep "$backoff"; then
        continue
      fi
      backoff=$(grok_next_backoff "$backoff")
      continue
    fi

    version=$(grok_installed_version)

    if ! grok_logged_in; then
      rc=0
      grok_run_login "$label" || rc=$?
      if [[ "$rc" -eq 10 || "$rc" -eq 0 ]]; then
        backoff=2
        continue
      fi
      if ! grok_sleep "$backoff"; then
        continue
      fi
      backoff=$(grok_next_backoff "$backoff")
      continue
    fi

    rc=0
    grok_run_connect "$permission" "$label" || rc=$?
    if [[ "$rc" -eq 10 ]]; then
      backoff=2
      continue
    fi
    if [[ "${GROKBOT_LAST_RUN_SECONDS:-0}" -gt 30 ]]; then
      backoff=2
    fi
    error=$(grok_tail_error "${GROKBOT_STATE_DIR}/connect.err")
    version=$(grok_installed_version)
    if [[ "$rc" -eq 78 ]] || ! grok_logged_in; then
      if [[ -z "$error" ]]; then
        error="The session ended. Sign in again."
        grok_log error "$error"
      elif ! grok_forwards_client_log; then
        grok_log error "$error"
      fi
      grok_write_status "signed_out" "Not signed in" "" "$error" "$version" "" "$label" ""
      backoff=2
      continue
    fi
    if [[ -z "$error" ]]; then
      error="The client stopped (exit ${rc}) and will restart."
      grok_log error "$error"
    elif ! grok_forwards_client_log; then
      grok_log error "$error"
    fi
    grok_write_status "restarting" "Connected as ${label}" "" "$error" "$version" "$(grok_account_email)" "$label" ""
    if ! grok_sleep "$backoff"; then
      continue
    fi
    backoff=$(grok_next_backoff "$backoff")
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  grok_main "$@"
fi
