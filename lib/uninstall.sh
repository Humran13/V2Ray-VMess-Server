#!/usr/bin/env bash
# uninstall.sh - remove only what this project owns.

if [[ -n "${VMESS_UNINSTALL_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_UNINSTALL_LOADED=1

uninstall_stop_and_disable() {
  if has_systemd; then
    systemctl stop "$VMESS_SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl disable "$VMESS_SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f "$VMESS_SERVICE_UNIT_PATH"
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

# Mode "keep": remove program + service, keep /etc/v2ray-vmess-server (config, users, backups).
# Mode "purge": also remove /etc/v2ray-vmess-server entirely and the xray binary if we installed it.
uninstall_run() {
  local mode=$1
  uninstall_stop_and_disable
  firewall_close_all_owned

  rm -f "$VMESS_MANAGER_LINK"
  rm -rf "$VMESS_APP_DIR"
  rm -f "$VMESS_ACME_HOOK" 2>/dev/null || true

  if [[ "$mode" == "purge" ]]; then
    local owns_xray=""
    [[ -f "$VMESS_STATE_FILE" ]] && owns_xray=$(state_get '.owns_xray_binary' 2>/dev/null)
    if [[ "$owns_xray" == "true" ]]; then
      rm -f "$VMESS_XRAY_BIN"
      log_info "Removed Xray binary (installed by this project)."
    else
      log_info "Left Xray binary in place (it pre-existed before this installer ran)."
    fi
    rm -rf "$VMESS_STATE_DIR"
    rm -rf "$VMESS_LOG_DIR"
    log_ok "Purged all V2Ray VMess Server data."
  else
    log_ok "Removed program files. Configuration, users, and backups were kept in $VMESS_STATE_DIR."
  fi
}
