#!/usr/bin/env bash
# os.sh - OS/architecture detection and feature probing.

if [[ -n "${VMESS_OS_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_OS_LOADED=1

OS_ID=""; OS_VERSION_ID=""; OS_CODENAME=""; OS_ARCH=""; OS_XRAY_ARCH=""

detect_os() {
  if [[ ! -r /etc/os-release ]]; then
    die "Cannot detect OS: /etc/os-release not found. This installer supports Ubuntu."
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-unknown}"
  OS_VERSION_ID="${VERSION_ID:-0}"
  OS_CODENAME="${VERSION_CODENAME:-unknown}"

  if [[ "$OS_ID" != "ubuntu" ]]; then
    log_warn "Detected OS '$OS_ID', not Ubuntu. This project targets Ubuntu 18.04-26.04+; continuing on a best-effort basis."
  fi

  local major
  major=$(echo "$OS_VERSION_ID" | cut -d. -f1)
  if [[ "$OS_ID" == "ubuntu" ]]; then
    if (( major > 26 )); then
      log_warn "Ubuntu version $OS_VERSION_ID is newer than the versions explicitly tested by this project (18.04-26.04). Continuing with feature detection."
    elif (( major < 18 )); then
      die "Ubuntu $OS_VERSION_ID is older than the minimum supported version (18.04)."
    fi
  fi
}

detect_arch() {
  local m
  m=$(uname -m)
  case "$m" in
    x86_64|amd64) OS_ARCH="amd64"; OS_XRAY_ARCH="64" ;;
    aarch64|arm64) OS_ARCH="arm64"; OS_XRAY_ARCH="arm64-v8a" ;;
    armv7l) OS_ARCH="armhf"; OS_XRAY_ARCH="arm32-v7a" ;;
    *) die "Unsupported architecture: $m (this project supports amd64/x86_64 and arm64/aarch64)" ;;
  esac
}

# Feature detection instead of hardcoding by version -------------------
has_systemd() {
  [[ -d /run/systemd/system ]] && have_cmd systemctl
}

package_manager() {
  if have_cmd apt-get; then echo "apt"; else echo "unknown"; fi
}

apt_install() {
  local pkgs=("$@")
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq -o Dpkg::Use-Pty=0 >/tmp/vmess-apt-update.log 2>&1 || {
    log_warn "apt-get update reported issues (see /tmp/vmess-apt-update.log); continuing."
  }
  apt-get install -y -qq -o Dpkg::Use-Pty=0 "${pkgs[@]}" >/tmp/vmess-apt-install.log 2>&1 \
    || die "Failed to install packages: ${pkgs[*]} (see /tmp/vmess-apt-install.log)"
}

ensure_dependencies() {
  local missing=() needed=(curl jq unzip tar openssl ca-certificates cron uuid-runtime)
  for c in curl jq unzip tar openssl; do
    have_cmd "$c" || missing+=("$c")
  done
  have_cmd uuidgen || missing+=(uuid-runtime)
  if [[ "${#missing[@]}" -gt 0 ]]; then
    if [[ "$(package_manager)" != "apt" ]]; then
      die "Missing dependencies (${missing[*]}) and no supported package manager found."
    fi
    log_info "Installing dependencies: ${needed[*]}"
    apt_install "${needed[@]}"
  fi
  have_cmd flock || apt_install util-linux || true
}

check_time_sync() {
  local mechanism="none" synced="unknown"
  if have_cmd timedatectl; then
    local out
    out=$(timedatectl show 2>/dev/null || timedatectl status 2>/dev/null || true)
    if echo "$out" | grep -qi "NTPSynchronized=yes\|synchronized: yes\|System clock synchronized: yes"; then
      synced="yes"
    else
      synced="no"
    fi
    if systemctl is-active --quiet systemd-timesyncd 2>/dev/null; then
      mechanism="systemd-timesyncd"
    elif systemctl is-active --quiet chronyd 2>/dev/null || systemctl is-active --quiet chrony 2>/dev/null; then
      mechanism="chrony"
    elif systemctl is-active --quiet ntp 2>/dev/null; then
      mechanism="ntp"
    fi
  fi
  echo "${mechanism}:${synced}"
}

ensure_time_sync() {
  local status mechanism synced
  status=$(check_time_sync)
  mechanism=${status%%:*}; synced=${status##*:}
  if [[ "$mechanism" == "none" ]]; then
    if has_systemd; then
      log_info "No time sync service active; enabling systemd-timesyncd."
      systemctl enable --now systemd-timesyncd >/dev/null 2>&1 || log_warn "Could not enable systemd-timesyncd."
    fi
  fi
  status=$(check_time_sync)
  synced=${status##*:}
  if [[ "$synced" == "no" ]]; then
    log_warn "System clock does not appear synchronized. VMess requires accurate time; connections may fail."
  else
    log_ok "System time synchronization looks healthy."
  fi
}
