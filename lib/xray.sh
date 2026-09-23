#!/usr/bin/env bash
# xray.sh - install/update the official Xray-core binary from GitHub releases,
# verifying integrity via the upstream .dgst SHA256 digest file.

if [[ -n "${VMESS_XRAY_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_XRAY_LOADED=1

XRAY_GH_API="https://api.github.com/repos/XTLS/Xray-core"
XRAY_GH_DL="https://github.com/XTLS/Xray-core/releases/download"

# Latest stable (non-prerelease, non-draft) tag. GitHub's /releases/latest
# endpoint already excludes prereleases and drafts.
xray_latest_stable_tag() {
  local tag
  tag=$(curl -fsSL --max-time 15 "${XRAY_GH_API}/releases/latest" 2>/dev/null | jq -r '.tag_name')
  [[ -z "$tag" || "$tag" == "null" ]] && die "Could not determine the latest stable Xray-core release from GitHub."
  echo "$tag"
}

# xray_install_version <tag> -> downloads, verifies sha256 via .dgst, installs binary.
xray_install_version() {
  local tag=$1
  local zip="Xray-linux-${OS_XRAY_ARCH}.zip"
  local url="${XRAY_GH_DL}/${tag}/${zip}"
  local dgst_url="${url}.dgst"
  local tmpdir
  tmpdir=$(mktemp -d)
  push_rollback "rm -rf '$tmpdir'"

  log_info "Downloading Xray-core ${tag} (${OS_XRAY_ARCH})..."
  curl -fsSL --max-time 120 -o "${tmpdir}/${zip}" "$url" || die "Failed to download $url"
  curl -fsSL --max-time 30 -o "${tmpdir}/${zip}.dgst" "$dgst_url" || die "Failed to download checksum file $dgst_url"

  local expected actual
  expected=$(awk -F'= ' '/256=/ {print $2}' "${tmpdir}/${zip}.dgst" | tr -d ' \r' | head -1)
  actual=$(sha256sum "${tmpdir}/${zip}" | awk '{print $1}')
  [[ -n "$expected" ]] || die "Could not parse expected SHA256 from digest file."
  if [[ "${expected,,}" != "${actual,,}" ]]; then
    die "SHA256 checksum mismatch for Xray-core ${tag}: expected $expected, got $actual"
  fi
  log_ok "Checksum verified for Xray-core ${tag}."

  unzip -oq "${tmpdir}/${zip}" -d "$tmpdir" || die "Failed to unzip Xray-core archive."
  [[ -f "${tmpdir}/xray" ]] || die "xray binary missing from downloaded archive."

  local prev_backup=""
  if [[ -x "$VMESS_XRAY_BIN" ]]; then
    prev_backup=$(mktemp)
    cp -f "$VMESS_XRAY_BIN" "$prev_backup"
  fi

  install -m 0755 "${tmpdir}/xray" "$VMESS_XRAY_BIN"
  if [[ -d "${tmpdir}/geoip.dat" || -f "${tmpdir}/geoip.dat" ]]; then
    ensure_dir /usr/local/share/xray 0755
    cp -f "${tmpdir}"/geo*.dat /usr/local/share/xray/ 2>/dev/null || true
  fi

  if ! "$VMESS_XRAY_BIN" version >/dev/null 2>&1; then
    log_err "Newly installed xray binary failed to run."
    if [[ -n "$prev_backup" ]]; then
      install -m 0755 "$prev_backup" "$VMESS_XRAY_BIN"
      log_warn "Restored previous xray binary."
    fi
    rm -rf "$tmpdir" "$prev_backup"
    die "Xray installation failed."
  fi

  [[ -n "$prev_backup" ]] && rm -f "$prev_backup"
  rm -rf "$tmpdir"
  clear_rollback
  log_ok "Xray-core ${tag} installed at $VMESS_XRAY_BIN."
}

xray_installed_tag() {
  if [[ -x "$VMESS_XRAY_BIN" ]]; then
    "$VMESS_XRAY_BIN" version 2>/dev/null | awk 'NR==1{print "v"$2}'
  else
    echo ""
  fi
}
