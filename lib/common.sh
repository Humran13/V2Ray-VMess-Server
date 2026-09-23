#!/usr/bin/env bash
# common.sh - shared logging, filesystem, and safety helpers.
# Sourced by install.sh and every lib/*.sh module. Must not be executed directly.

if [[ -n "${VMESS_COMMON_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
VMESS_COMMON_LOADED=1

set -o pipefail

# --- Paths -------------------------------------------------------------
VMESS_APP_DIR="${VMESS_APP_DIR:-/opt/v2ray-vmess-server}"
VMESS_STATE_DIR="${VMESS_STATE_DIR:-/etc/v2ray-vmess-server}"
VMESS_LIB_DIR="${VMESS_APP_DIR}/lib"
VMESS_BACKUP_DIR="${VMESS_STATE_DIR}/backups"
VMESS_CERT_DIR="${VMESS_STATE_DIR}/certs"
VMESS_REALITY_DIR="${VMESS_STATE_DIR}/reality"
VMESS_USERS_FILE="${VMESS_STATE_DIR}/users.json"
VMESS_STATE_FILE="${VMESS_STATE_DIR}/state.json"
VMESS_XRAY_CONFIG="${VMESS_STATE_DIR}/config.json"
VMESS_XRAY_BIN="/usr/local/bin/xray"
VMESS_MANAGER_LINK="/usr/local/bin/vmess"
VMESS_SERVICE_NAME="v2ray-vmess-server"
VMESS_LOG_DIR="/var/log/v2ray-vmess-server"

# --- Colors (disabled when not a tty or NO_COLOR set) -------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YEL=$'\033[0;33m'
  C_BLU=$'\033[0;34m'; C_CYN=$'\033[0;36m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_CYN=""; C_BLD=""; C_RST=""
fi

log_info()  { printf '%s[*]%s %s\n' "$C_BLU" "$C_RST" "$*" >&2; }
log_ok()    { printf '%s[OK]%s %s\n' "$C_GRN" "$C_RST" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
log_err()   { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
log_step()  { printf '\n%s%s==>%s %s%s\n' "$C_BLD" "$C_CYN" "$C_RST" "$C_BLD" "$*$C_RST" >&2; }
die()       { log_err "$*"; exit 1; }

# --- Root / privilege ----------------------------------------------------
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "This action requires root. Re-run with sudo."
  fi
}

# --- TTY-safe interactive input (works under curl|sudo bash) -------------
# Reads a line from the controlling terminal even when stdin is a pipe.
tty_read() {
  local __varname=$1 __prompt=${2:-}
  local __val=""
  if [[ -r /dev/tty ]]; then
    if [[ -n "$__prompt" ]]; then printf '%s' "$__prompt" > /dev/tty; fi
    IFS= read -r __val < /dev/tty || true
  elif [[ -t 0 ]]; then
    if [[ -n "$__prompt" ]]; then printf '%s' "$__prompt"; fi
    IFS= read -r __val || true
  else
    __val=""
  fi
  printf -v "$__varname" '%s' "$__val"
}

is_interactive() {
  [[ -r /dev/tty ]] || [[ -t 0 ]]
}

confirm() {
  local prompt=${1:-"Continue?"} default=${2:-N} ans
  if [[ "${VMESS_ASSUME_YES:-0}" == "1" ]]; then return 0; fi
  if ! is_interactive; then
    [[ "$default" == "Y" ]] && return 0 || return 1
  fi
  local suffix="[y/N]"; [[ "$default" == "Y" ]] && suffix="[Y/n]"
  tty_read ans "$prompt $suffix "
  ans=${ans:-$default}
  [[ "$ans" =~ ^[Yy]$ ]]
}

# --- Filesystem helpers ---------------------------------------------------
ensure_dir() {
  local dir=$1 mode=${2:-0750}
  mkdir -p "$dir"
  chmod "$mode" "$dir"
}

# Atomically write $content to $path with $mode permissions.
atomic_write() {
  local path=$1 content=$2 mode=${3:-0640}
  local dir tmp
  dir=$(dirname "$path")
  ensure_dir "$dir" 0750
  tmp=$(mktemp "${dir}/.tmp.XXXXXX")
  printf '%s' "$content" > "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
}

# Atomically write $src_file to $path with $mode permissions.
atomic_write_file() {
  local src_file=$1 path=$2 mode=${3:-0640}
  local dir tmp
  dir=$(dirname "$path")
  ensure_dir "$dir" 0750
  tmp=$(mktemp "${dir}/.tmp.XXXXXX")
  cp -f "$src_file" "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$path"
}

# Simple flock-based critical section: with_lock <lockfile> <command...>
with_lock() {
  local lockfile=$1; shift
  ensure_dir "$(dirname "$lockfile")" 0750
  exec {__lockfd}>"$lockfile"
  if ! flock -w 15 "$__lockfd"; then
    die "Could not acquire lock: $lockfile"
  fi
  "$@"
  local rc=$?
  flock -u "$__lockfd"
  exec {__lockfd}>&-
  return $rc
}

# --- Rollback trap stack ---------------------------------------------------
declare -a VMESS_ROLLBACK_STACK=()
push_rollback() { VMESS_ROLLBACK_STACK+=("$1"); }
clear_rollback() { VMESS_ROLLBACK_STACK=(); }
run_rollback() {
  local i
  for (( i=${#VMESS_ROLLBACK_STACK[@]}-1; i>=0; i-- )); do
    log_warn "Rollback: ${VMESS_ROLLBACK_STACK[$i]}"
    eval "${VMESS_ROLLBACK_STACK[$i]}" || true
  done
  clear_rollback
}

# --- Command / dependency checks -------------------------------------------
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# --- Version helpers ---------------------------------------------------
manager_version() {
  if [[ -f "${VMESS_APP_DIR}/VERSION" ]]; then
    cat "${VMESS_APP_DIR}/VERSION"
  else
    echo "unknown"
  fi
}

xray_version() {
  if [[ -x "$VMESS_XRAY_BIN" ]]; then
    "$VMESS_XRAY_BIN" version 2>/dev/null | awk 'NR==1{print $2}'
  else
    echo "not-installed"
  fi
}

json_get() { # json_get <file> <jq-filter>
  jq -r "$2" "$1" 2>/dev/null
}
