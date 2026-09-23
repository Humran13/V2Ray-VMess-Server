#!/usr/bin/env bash
# backup.sh - timestamped backups of project state, with path-traversal-safe restore.

if [[ -n "${VMESS_BACKUP_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_BACKUP_LOADED=1

backup_create() {
  ensure_dir "$VMESS_BACKUP_DIR" 0750
  local ts file
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  file="${VMESS_BACKUP_DIR}/vmess-backup-${ts}.tar.gz"
  local -a entries=()
  [[ -f "$VMESS_STATE_FILE" ]] && entries+=("etc/v2ray-vmess-server/state.json") || true
  [[ -f "$VMESS_USERS_FILE" ]] && entries+=("etc/v2ray-vmess-server/users.json") || true
  [[ -f "$VMESS_XRAY_CONFIG" ]] && entries+=("etc/v2ray-vmess-server/config.json") || true
  [[ -d "$VMESS_REALITY_DIR" ]] && entries+=("etc/v2ray-vmess-server/reality") || true
  [[ -d "$VMESS_CERT_DIR" ]] && entries+=("etc/v2ray-vmess-server/certs") || true
  if (( ${#entries[@]} == 0 )); then die "Nothing to back up yet (no project state found)."; fi

  tar -czf "$file" \
    --transform "s|^|v2ray-vmess-server-backup/|" \
    -C / "${entries[@]}" \
    2>/tmp/vmess-backup.log || die "Backup failed (see /tmp/vmess-backup.log)."
  chmod 0600 "$file"
  echo "$file"
}

# Reject archives containing absolute paths or ".." traversal segments.
backup_verify_safe() {
  local file=$1 entry
  tar -tzf "$file" 2>/dev/null | while IFS= read -r entry; do
    if [[ "$entry" == /* || "$entry" == *".."* ]]; then
      echo "unsafe:$entry"
      break
    fi
  done
  return 0
}

backup_restore() {
  local file=$1
  [[ -f "$file" ]] || die "Backup file not found: $file"
  local unsafe
  unsafe=$(backup_verify_safe "$file")
  if [[ -n "$unsafe" ]]; then
    die "Refusing to restore backup: unsafe archive entry detected ($unsafe)"
  fi

  log_info "Backing up current state before restore..."
  local pre_restore
  pre_restore=$(backup_create)
  log_info "Pre-restore snapshot saved to $pre_restore"

  local tmp
  tmp=$(mktemp -d)
  tar -xzf "$file" -C "$tmp" || die "Failed to extract backup archive."
  local src="${tmp}/v2ray-vmess-server-backup/etc/v2ray-vmess-server"
  [[ -d "$src" ]] || die "Backup archive does not contain expected project data."

  ensure_dir "$VMESS_STATE_DIR" 0750
  [[ -f "${src}/state.json" ]] && atomic_write_file "${src}/state.json" "$VMESS_STATE_FILE" 0640
  [[ -f "${src}/users.json" ]] && atomic_write_file "${src}/users.json" "$VMESS_USERS_FILE" 0640
  [[ -d "${src}/reality" ]] && { ensure_dir "$VMESS_REALITY_DIR" 0700; cp -rf "${src}/reality/." "$VMESS_REALITY_DIR/"; }
  [[ -d "${src}/certs" ]] && { ensure_dir "$VMESS_CERT_DIR" 0750; cp -rf "${src}/certs/." "$VMESS_CERT_DIR/"; }

  if ! config_apply; then
    log_err "Restored configuration failed to apply. Restoring pre-restore snapshot."
    backup_restore "$pre_restore"
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  log_ok "Restore completed and verified healthy."
}

backup_list() {
  ensure_dir "$VMESS_BACKUP_DIR" 0750
  ls -1t "$VMESS_BACKUP_DIR"/vmess-backup-*.tar.gz 2>/dev/null
}
