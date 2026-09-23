#!/usr/bin/env bash
# install.sh - V2Ray VMess Server installer (Xray-core based).
# Safe to run via: curl -fsSL <raw-url>/install.sh | sudo bash
#
# When piped through `curl | bash`, this file has no sibling lib/ directory
# on disk, so it fetches the full project into /opt/v2ray-vmess-server first,
# then re-executes its real logic from that checked-out copy.
set -Eeuo pipefail

VMESS_REPO_OWNER="Humran13"
VMESS_REPO_NAME="V2Ray-VMess-Server"
VMESS_REPO_BRANCH="main"
VMESS_APP_DIR="${VMESS_APP_DIR:-/opt/v2ray-vmess-server}"

_self_dir() {
  local src="${BASH_SOURCE[0]:-}"
  if [[ -n "$src" && -f "$src" ]]; then
    (cd "$(dirname "$src")" && pwd)
  else
    echo ""
  fi
}

_fetch_project_into_app_dir() {
  local tmp url
  tmp=$(mktemp -d)
  url="https://github.com/${VMESS_REPO_OWNER}/${VMESS_REPO_NAME}/archive/refs/heads/${VMESS_REPO_BRANCH}.tar.gz"
  echo "[*] Fetching V2Ray VMess Server project files..." >&2
  if ! curl -fsSL --max-time 60 -o "${tmp}/src.tar.gz" "$url"; then
    echo "[ERROR] Failed to download project archive from $url" >&2
    exit 1
  fi
  tar -xzf "${tmp}/src.tar.gz" -C "$tmp"
  local extracted
  extracted=$(find "$tmp" -maxdepth 1 -type d -name "${VMESS_REPO_NAME}-*" | head -1)
  [[ -d "$extracted" ]] || { echo "[ERROR] Unexpected archive layout." >&2; exit 1; }
  mkdir -p "$VMESS_APP_DIR"
  cp -rf "${extracted}/." "$VMESS_APP_DIR/"
  rm -rf "$tmp"
}

MAIN_SCRIPT_DIR="$(_self_dir)"
if [[ -z "$MAIN_SCRIPT_DIR" || ! -f "${MAIN_SCRIPT_DIR}/lib/common.sh" ]]; then
  if [[ -f "${VMESS_APP_DIR}/lib/common.sh" && "${VMESS_FORCE_REFETCH:-0}" != "1" ]]; then
    MAIN_SCRIPT_DIR="$VMESS_APP_DIR"
  else
    _fetch_project_into_app_dir
    MAIN_SCRIPT_DIR="$VMESS_APP_DIR"
  fi
fi

# shellcheck source=lib/common.sh
source "${MAIN_SCRIPT_DIR}/lib/common.sh"
for f in os validate transports tls reality users config xray network firewall service client menu backup update diagnostics uninstall; do
  # shellcheck disable=SC1090
  source "${MAIN_SCRIPT_DIR}/lib/${f}.sh"
done

require_root

# --- Argument parsing ------------------------------------------------------
OPT_TRANSPORT=""; OPT_SECURITY=""; OPT_PORT=""; OPT_DOMAIN=""; OPT_USER=""
OPT_EMAIL=""; OPT_CERT=""; OPT_KEY=""; OPT_REALITY_TARGET=""; OPT_SELFSIGNED=0
VMESS_ASSUME_YES=0

print_usage() {
  cat <<'EOF'
Usage: install.sh [options]

  --transport <raw|xhttp|websocket|grpc|httpupgrade|mkcp|hysteria>
  --security  <none|tls|reality>
  --port <1-65535>
  --domain <domain>            Required for TLS/ACME.
  --email <email>              Used for Let's Encrypt registration.
  --cert <path> --key <path>   Use an existing certificate instead of ACME.
  --reality-target <host:port> REALITY camouflage target (default: auto).
  --self-signed                 Use a self-signed cert (TESTING ONLY).
  --user <name>                 Initial VMess user name (default: user1).
  --yes                         Assume yes / non-interactive mode.
  -h, --help                    Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --transport) OPT_TRANSPORT=$2; shift 2 ;;
    --security) OPT_SECURITY=$2; shift 2 ;;
    --port) OPT_PORT=$2; shift 2 ;;
    --domain) OPT_DOMAIN=$2; shift 2 ;;
    --email) OPT_EMAIL=$2; shift 2 ;;
    --cert) OPT_CERT=$2; shift 2 ;;
    --key) OPT_KEY=$2; shift 2 ;;
    --reality-target) OPT_REALITY_TARGET=$2; shift 2 ;;
    --self-signed) OPT_SELFSIGNED=1; shift ;;
    --user) OPT_USER=$2; shift 2 ;;
    --yes) VMESS_ASSUME_YES=1; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) die "Unknown option: $1 (see --help)" ;;
  esac
done
export VMESS_ASSUME_YES

# --- Failure trap: rollback partial changes -------------------------------
_on_error() {
  local ec=$?
  log_err "Installation failed (exit $ec)."
  run_rollback
  exit "$ec"
}
trap _on_error ERR

# --- Existing installation detection ---------------------------------------
handle_existing_installation() {
  [[ -f "$VMESS_STATE_FILE" ]] || return 0
  log_warn "An existing V2Ray VMess Server installation was detected."
  if [[ "$VMESS_ASSUME_YES" == "1" ]]; then
    log_info "--yes given: proceeding to reconfigure the existing installation with any provided options."
    return 0
  fi
  if ! is_interactive; then
    log_info "Non-interactive session: keeping existing installation as-is. Run 'sudo vmess' to manage it."
    exit 0
  fi
  local choice
  menu_choose choice "Existing installation found. What would you like to do?" \
    "Manage existing installation (open the manager menu)" \
    "Repair installation" \
    "Upgrade Xray-core" \
    "Reinstall (backs up current config first)" \
    "Cancel"
  case "$choice" in
    1) exec "${VMESS_APP_DIR}/bin/vmess" ;;
    2) vmess_repair; exit $? ;;
    3) update_xray_core; exit $? ;;
    4) backup_create >/dev/null
       log_info "Existing config backed up. Continuing with a fresh install." ;;
    5) log_info "Cancelled."; exit 0 ;;
  esac
}

vmess_repair() {
  log_step "Repairing installation"
  ensure_dir "$VMESS_STATE_DIR" 0750
  ensure_dir "$VMESS_APP_DIR" 0755
  ensure_dependencies
  [[ -x "$VMESS_XRAY_BIN" ]] || die "Xray binary missing; run the installer fresh to reinstall it."
  ln -sf "${VMESS_APP_DIR}/bin/vmess" "$VMESS_MANAGER_LINK"
  service_install_unit
  if config_apply; then log_ok "Repair completed; service is healthy."; else die "Repair failed: service unhealthy after reapplying configuration."; fi
}

# --- Step: pre-flight ---------------------------------------------------
log_step "V2Ray VMess Server Installer"
detect_os
detect_arch
log_ok "OS: ${OS_ID} ${OS_VERSION_ID} (${OS_CODENAME}) | Arch: ${OS_ARCH}"

handle_existing_installation

log_step "Checking network connectivity"
check_internet || die "No internet connectivity detected. This installer needs to reach GitHub."
log_ok "Internet connectivity OK."

log_step "Installing dependencies"
ensure_dependencies
have_cmd qrencode || apt_install qrencode || log_warn "Could not install qrencode; QR codes will be skipped."
log_ok "Dependencies satisfied."

log_step "Checking time synchronization"
ensure_time_sync

# --- Step: choose transport/security -------------------------------------
choose_transport_security() {
  if [[ -n "$OPT_TRANSPORT" ]]; then
    TRANSPORT=$OPT_TRANSPORT
  elif [[ "$VMESS_ASSUME_YES" == "1" ]]; then
    TRANSPORT="raw"
  else
    local labels=() i
    for i in "${TRANSPORT_IDS[@]}"; do
      local note; note=$(transport_menu_note "$i")
      labels+=("$(transport_label "$i")$( [[ -n "$note" ]] && echo " - $note")")
    done
    local idx
    menu_choose idx "Choose a VMess transport (all are officially supported by current Xray-core):" "${labels[@]}"
    TRANSPORT="${TRANSPORT_IDS[$((idx-1))]}"
  fi
  require_valid "$TRANSPORT" valid_transport "transport"

  if [[ -n "$OPT_SECURITY" ]]; then
    SECURITY=$OPT_SECURITY
  elif [[ "$VMESS_ASSUME_YES" == "1" ]]; then
    if transport_security_supported "$TRANSPORT" reality; then SECURITY="reality"; else SECURITY="tls"; fi
  else
    local secs=() s
    while IFS= read -r s; do
      local tag=""
      transport_security_recommended "$TRANSPORT" "$s" && tag=" (recommended)"
      secs+=("$s${tag}")
    done < <(list_supported_securities "$TRANSPORT")
    local sidx
    menu_choose sidx "Choose transport security for $(transport_label "$TRANSPORT"):" "${secs[@]}"
    SECURITY=$(echo "${secs[$((sidx-1))]}" | awk '{print $1}')
  fi
  if ! transport_security_supported "$TRANSPORT" "$SECURITY"; then
    die "$(transport_label "$TRANSPORT") does not support security '$SECURITY' per current Xray-core. See docs/TRANSPORTS.md."
  fi
  log_ok "Selected: VMess + $(transport_label "$TRANSPORT") + ${SECURITY}"
}

log_step "Connection mode"
choose_transport_security

# --- Step: port -------------------------------------------------------------
choose_port() {
  local default_port=443
  if [[ -n "$OPT_PORT" ]]; then PORT=$OPT_PORT
  elif [[ "$VMESS_ASSUME_YES" == "1" ]]; then PORT=$default_port
  else menu_input PORT "Server port" "$default_port"
  fi
  require_valid "$PORT" valid_port "port"
  local proto="tcp"; transport_is_udp "$TRANSPORT" && proto="udp"
  if port_in_use "$PORT" "$proto"; then
    log_warn "Port ${PORT}/${proto} appears to already be in use."
    if [[ "$VMESS_ASSUME_YES" != "1" ]] && is_interactive; then
      confirm "Continue anyway?" N || die "Aborted due to port conflict."
    fi
  fi
}
log_step "Network port"
choose_port

# --- Step: domain / TLS / REALITY -------------------------------------------
DOMAIN=""; TLS_MODE="none"; CERT_PATH=""; KEY_PATH=""
setup_security_material() {
  ensure_dir "$VMESS_STATE_DIR" 0750
  PUB_IPV4=$(detect_public_ipv4 || echo "")
  [[ -z "$PUB_IPV4" ]] && log_warn "Could not auto-detect public IPv4."

  if [[ "$SECURITY" == "tls" ]]; then
    if [[ -n "$OPT_DOMAIN" ]]; then DOMAIN=$OPT_DOMAIN
    elif [[ "$VMESS_ASSUME_YES" != "1" ]]; then menu_input DOMAIN "Domain name pointing at this server"
    fi
    if [[ -n "$OPT_CERT" && -n "$OPT_KEY" ]]; then
      require_valid "$OPT_CERT" valid_safe_path "certificate path"
      require_valid "$OPT_KEY" valid_safe_path "key path"
      read -r CERT_PATH KEY_PATH <<< "$(tls_use_custom "$OPT_CERT" "$OPT_KEY")"
      TLS_MODE="custom"
    elif [[ "$OPT_SELFSIGNED" == "1" ]]; then
      read -r CERT_PATH KEY_PATH <<< "$(tls_self_signed "${DOMAIN:-$PUB_IPV4}")"
      TLS_MODE="selfsigned"
    else
      require_valid "$DOMAIN" valid_domain "domain"
      if [[ -n "$PUB_IPV4" ]] && ! tls_dns_matches_public_ip "$DOMAIN" "$PUB_IPV4"; then
        log_warn "DNS for $DOMAIN does not yet resolve to this server's IP ($PUB_IPV4)."
        if [[ "$VMESS_ASSUME_YES" != "1" ]] && is_interactive; then
          confirm "Continue with Let's Encrypt anyway (may fail)?" N || die "Aborted: fix DNS then re-run."
        fi
      fi
      tls_obtain_acme "$DOMAIN" "$OPT_EMAIL"
      read -r CERT_PATH KEY_PATH <<< "$(tls_cert_paths_for_domain "$DOMAIN")"
      TLS_MODE="acme"
    fi
  elif [[ "$SECURITY" == "reality" ]]; then
    log_info "Generating REALITY key material..."
    read -r REALITY_PRIV REALITY_PUB <<< "$(reality_generate_keypair)"
    REALITY_SID=$(reality_generate_short_id)
    if [[ -n "$OPT_REALITY_TARGET" ]]; then REALITY_TARGET=$OPT_REALITY_TARGET
    elif [[ "$VMESS_ASSUME_YES" == "1" ]]; then REALITY_TARGET=$(reality_pick_default_target)
    else menu_input REALITY_TARGET "REALITY camouflage target (host:port)" "$(reality_pick_default_target)"
    fi
    reality_validate_target "$REALITY_TARGET" || die "REALITY target validation failed."
    REALITY_SNI="${REALITY_TARGET%:*}"
  elif [[ "$TRANSPORT" == "hysteria" ]]; then
    : # hysteria requires tls; handled by matrix validation above
  fi

  if [[ "$TRANSPORT" == "hysteria" && "$SECURITY" != "tls" ]]; then
    die "VMess + Hysteria transport requires TLS security."
  fi
}

# --- Step: install Xray-core -------------------------------------------------
# Must happen before REALITY key generation, which shells out to `xray x25519`.
log_step "Installing Xray-core"
OWNS_XRAY_BINARY=false
if [[ ! -x "$VMESS_XRAY_BIN" ]]; then OWNS_XRAY_BINARY=true; fi
# Preserve ownership across "uninstall (keep data) then reinstall": once this
# project has claimed the binary, a later reinstall must not un-claim it just
# because the binary happens to still be present on disk.
if [[ -f "$VMESS_STATE_FILE" ]] && [[ "$(state_get_raw '.owns_xray_binary' 2>/dev/null)" == "true" ]]; then
  OWNS_XRAY_BINARY=true
fi
LATEST_TAG=$(xray_latest_stable_tag)
xray_install_version "$LATEST_TAG"

log_step "TLS / REALITY setup"
setup_security_material

# --- Step: build state + config ---------------------------------------------
log_step "Generating configuration"
state_init_default
users_init

HYSTERIA_AUTH=""
[[ "$TRANSPORT" == "hysteria" ]] && HYSTERIA_AUTH=$(openssl rand -hex 16)
GRPC_SERVICE="vmess-grpc-$(openssl rand -hex 3)"
MKCP_SEED=$(openssl rand -hex 8)
WS_PATH="/$(openssl rand -hex 4)"
XHTTP_PATH="/$(openssl rand -hex 4)"
HTTPUPGRADE_PATH="/$(openssl rand -hex 4)"

LISTEN_ADDR=""
has_ipv6 && LISTEN_ADDR="::"

STATE_JSON=$(jq -n \
  --arg transport "$TRANSPORT" --arg security "$SECURITY" --argjson port "$PORT" \
  --arg domain "${DOMAIN:-}" --arg ip "${PUB_IPV4:-}" --arg listen "$LISTEN_ADDR" \
  --arg ws "$WS_PATH" --arg xh "$XHTTP_PATH" --arg hu "$HTTPUPGRADE_PATH" \
  --arg grpc "$GRPC_SERVICE" --arg seed "$MKCP_SEED" --arg hauth "$HYSTERIA_AUTH" \
  --arg rpriv "${REALITY_PRIV:-}" --arg rpub "${REALITY_PUB:-}" --arg rsid "${REALITY_SID:-}" \
  --arg rtarget "${REALITY_TARGET:-}" --arg rsni "${REALITY_SNI:-}" \
  --arg cert "${CERT_PATH:-}" --arg key "${KEY_PATH:-}" --arg tlsmode "$TLS_MODE" --arg tdomain "${DOMAIN:-}" --arg email "${OPT_EMAIL:-}" \
  --arg xver "$LATEST_TAG" --arg mver "$(cat "${MAIN_SCRIPT_DIR}/VERSION")" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson owns "$OWNS_XRAY_BINARY" \
  '{
    transport:$transport, security:$security, port:$port, domain:$domain, server_ip:$ip, listen:$listen,
    ws_path:$ws, xhttp_path:$xh, httpupgrade_path:$hu, grpc_service_name:$grpc, mkcp_seed:$seed, hysteria_auth:$hauth,
    reality:{private_key:$rpriv, public_key:$rpub, short_ids:[$rsid], target:$rtarget, server_names:[$rsni]},
    tls:{mode:$tlsmode, cert:$cert, key:$key, domain:$tdomain, email:$email},
    xray_version:$xver, manager_version:$mver, installed_at:$now, owns_xray_binary:$owns, owns_service:true,
    firewall_owned_rules:[]
  }')
atomic_write "$VMESS_STATE_FILE" "$STATE_JSON" 0640

# --- Step: initial user ------------------------------------------------------
INITIAL_USER=${OPT_USER:-user1}
require_valid "$INITIAL_USER" valid_username "username"
if users_exists "$INITIAL_USER"; then
  USER_UUID=$(users_get_uuid "$INITIAL_USER")
  log_info "User '$INITIAL_USER' already exists; keeping existing UUID."
else
  USER_UUID=$(users_add "$INITIAL_USER")
fi

# --- Step: firewall -----------------------------------------------------------
log_step "Configuring firewall"
PROTO="tcp"; transport_is_udp "$TRANSPORT" && PROTO="udp"
firewall_open "$PORT" "$PROTO"
[[ "$TLS_MODE" == "acme" ]] && firewall_open 80 tcp

# --- Step: install app files, service, manager --------------------------------
log_step "Installing application and service"
if [[ "$MAIN_SCRIPT_DIR" != "$VMESS_APP_DIR" ]]; then
  ensure_dir "$VMESS_APP_DIR" 0755
  cp -rf "${MAIN_SCRIPT_DIR}/." "$VMESS_APP_DIR/" 2>/dev/null || true
fi
chmod 0755 "${VMESS_APP_DIR}/bin/vmess" 2>/dev/null || true
ln -sf "${VMESS_APP_DIR}/bin/vmess" "$VMESS_MANAGER_LINK"
service_install_unit

log_step "Validating and starting service"
if ! config_apply; then
  die "Service failed to start with the generated configuration. Check the messages above."
fi
service_enable_start >/dev/null
log_ok "Service is active and healthy."

# --- Step: summary -------------------------------------------------------------
print_banner "V2Ray VMess Server - Installation Complete"
print_kv "Xray Version" "$(xray_version)"
print_kv "Mode" "VMess + $(transport_label "$TRANSPORT")"
print_kv "Security" "$SECURITY"
print_kv "Server" "$(client_server_address)"
print_kv "Port" "$PORT"
print_kv "User" "$INITIAL_USER"
print_kv "UUID" "$USER_UUID"
print_kv "Manager" "sudo vmess"
echo "================================================"
echo

URI=$(client_build_uri "$INITIAL_USER")
if [[ -n "$URI" ]]; then
  echo "VMess link:"
  echo "$URI"
  echo
  client_qr_render "$URI"
else
  caveat=$(client_uri_caveat "$TRANSPORT")
  [[ -n "$caveat" ]] && log_warn "$caveat"
fi

echo
echo "Canonical client configuration (Xray-core JSON):"
client_build_config_json "$INITIAL_USER"
echo
log_ok "Run 'sudo vmess' to manage users, view diagnostics, backups, and more."
