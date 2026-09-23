#!/usr/bin/env bash
# firewall.sh - opens only the ports this project needs, and tracks exactly
# which rules it created so uninstall/repair can remove only its own rules.
# Never flushes or disables the user's firewall globally.

if [[ -n "${VMESS_FIREWALL_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_FIREWALL_LOADED=1

firewall_backend() {
  if have_cmd ufw && ufw status 2>/dev/null | grep -qi "^Status: active"; then
    echo "ufw"
  elif have_cmd nft && nft list ruleset >/dev/null 2>&1; then
    echo "nftables"
  elif have_cmd firewall-cmd && systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "firewalld"
  else
    echo "none"
  fi
}

_firewall_owned_add() {
  local rule=$1 new
  new=$(jq --arg r "$rule" '.firewall_owned_rules = ((.firewall_owned_rules // []) + [$r] | unique)' "$VMESS_STATE_FILE")
  atomic_write "$VMESS_STATE_FILE" "$new" 0640
}

_firewall_owned_remove() {
  local rule=$1 new
  new=$(jq --arg r "$rule" '.firewall_owned_rules = ((.firewall_owned_rules // []) - [$r])' "$VMESS_STATE_FILE")
  atomic_write "$VMESS_STATE_FILE" "$new" 0640
}

# firewall_open <port> <tcp|udp>
firewall_open() {
  local port=$1 proto=$2 backend rule
  require_valid "$port" valid_port "port"
  rule="${port}/${proto}"
  backend=$(firewall_backend)
  case "$backend" in
    ufw)
      ufw allow "${port}/${proto}" comment "v2ray-vmess-server" >/dev/null 2>&1 \
        && log_ok "UFW: opened ${rule}" || log_warn "UFW: failed to open ${rule}"
      ;;
    nftables)
      log_info "nftables detected but this installer does not auto-edit custom nft rulesets; ensure ${rule} is reachable."
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${port}/${proto}" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 \
        && log_ok "firewalld: opened ${rule}" || log_warn "firewalld: failed to open ${rule}"
      ;;
    none)
      log_info "No active managed firewall detected; skipping firewall rule for ${rule}."
      return 0
      ;;
  esac
  _firewall_owned_add "$rule"
}

firewall_close() {
  local port=$1 proto=$2 backend rule
  rule="${port}/${proto}"
  backend=$(firewall_backend)
  case "$backend" in
    ufw) ufw delete allow "${port}/${proto}" >/dev/null 2>&1 || true ;;
    firewalld) firewall-cmd --permanent --remove-port="${port}/${proto}" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 || true ;;
    *) : ;;
  esac
  _firewall_owned_remove "$rule"
}

firewall_close_all_owned() {
  local rules r port proto
  rules=$(jq -r '.firewall_owned_rules[]?' "$VMESS_STATE_FILE" 2>/dev/null)
  while IFS= read -r r; do
    if [[ -z "$r" ]]; then continue; fi
    port=${r%/*}; proto=${r#*/}
    firewall_close "$port" "$proto"
  done <<< "$rules"
}

firewall_status_summary() {
  local backend
  backend=$(firewall_backend)
  echo "backend=${backend}"
  if [[ "$backend" == "ufw" ]]; then
    ufw status numbered 2>/dev/null | grep -i "v2ray-vmess-server\|Status:"
  fi
}
