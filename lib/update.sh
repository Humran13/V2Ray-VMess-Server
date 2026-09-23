#!/usr/bin/env bash
# update.sh - safe updates for Xray-core and for this manager/project,
# each with backup + validation + automatic rollback on failure.

if [[ -n "${VMESS_UPDATE_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_UPDATE_LOADED=1

VMESS_REPO_RAW_BASE="https://raw.githubusercontent.com/Humran13/V2Ray-VMess-Server/main"
VMESS_REPO_TARBALL="https://github.com/Humran13/V2Ray-VMess-Server/archive/refs/heads/main.tar.gz"

update_xray_core() {
  local current latest
  current=$(xray_installed_tag)
  latest=$(xray_latest_stable_tag)
  log_info "Installed Xray-core: ${current:-none} | Latest stable: $latest"
  if [[ "$current" == "$latest" ]]; then
    log_ok "Xray-core is already up to date ($latest)."
    return 0
  fi

  local backup
  backup=$(backup_create)
  log_info "Pre-update backup: $backup"

  local prev_bin
  prev_bin=$(mktemp)
  [[ -x "$VMESS_XRAY_BIN" ]] && cp -f "$VMESS_XRAY_BIN" "$prev_bin"

  if ! xray_install_version "$latest"; then
    log_err "Failed to install Xray-core $latest."
    return 1
  fi

  if ! config_validate_file "$VMESS_XRAY_CONFIG"; then
    log_err "Existing configuration is not valid against Xray-core $latest. Rolling back binary."
    [[ -s "$prev_bin" ]] && install -m 0755 "$prev_bin" "$VMESS_XRAY_BIN"
    rm -f "$prev_bin"
    return 1
  fi

  if ! service_restart_and_check; then
    log_err "Service unhealthy after updating Xray-core. Rolling back binary."
    [[ -s "$prev_bin" ]] && install -m 0755 "$prev_bin" "$VMESS_XRAY_BIN"
    service_restart_and_check || log_err "Rollback restart also failed; manual intervention required."
    rm -f "$prev_bin"
    return 1
  fi

  rm -f "$prev_bin"
  state_set_kv "xray_version" "$latest"
  log_ok "Xray-core updated to $latest and verified healthy."
}

update_manager() {
  local tmp
  tmp=$(mktemp -d)
  log_info "Downloading latest manager/project files..."
  curl -fsSL --max-time 60 -o "${tmp}/repo.tar.gz" "$VMESS_REPO_TARBALL" \
    || die "Failed to download latest project archive."
  tar -xzf "${tmp}/repo.tar.gz" -C "$tmp" || die "Failed to extract project archive."
  local src
  src=$(find "$tmp" -maxdepth 1 -type d -name "V2Ray-VMess-Server-*" | head -1)
  [[ -d "$src" ]] || die "Unexpected archive layout."

  cp -rf "${src}/lib/." "${VMESS_APP_DIR}/lib/"
  cp -f "${src}/bin/vmess" "${VMESS_APP_DIR}/bin/vmess"
  cp -f "${src}/VERSION" "${VMESS_APP_DIR}/VERSION"
  chmod 0755 "${VMESS_APP_DIR}/bin/vmess"
  ln -sf "${VMESS_APP_DIR}/bin/vmess" "$VMESS_MANAGER_LINK"
  rm -rf "$tmp"
  log_ok "Manager updated to $(cat "${VMESS_APP_DIR}/VERSION")."
}
