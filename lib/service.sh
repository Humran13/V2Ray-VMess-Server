#!/usr/bin/env bash
# service.sh - systemd unit management for the Xray process.
# Uses a project-owned unit name (not "xray.service") so an unrelated,
# pre-existing Xray install on the same host is never touched.

if [[ -n "${VMESS_SERVICE_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_SERVICE_LOADED=1

VMESS_SERVICE_UNIT_PATH="/etc/systemd/system/${VMESS_SERVICE_NAME}.service"

service_unit_content() {
  cat <<EOF
[Unit]
Description=V2Ray VMess Server (Xray-core)
Documentation=https://github.com/Humran13/V2Ray-VMess-Server
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
NoNewPrivileges=true
ExecStart=${VMESS_XRAY_BIN} run -config ${VMESS_XRAY_CONFIG}
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
}

service_install_unit() {
  has_systemd || die "systemd is required to manage the service on this host."
  atomic_write "$VMESS_SERVICE_UNIT_PATH" "$(service_unit_content)" 0644
  systemctl daemon-reload
}

service_enable_start() {
  systemctl enable "$VMESS_SERVICE_NAME" >/dev/null 2>&1
  systemctl restart "$VMESS_SERVICE_NAME"
}

service_health_check() {
  local tries=${1:-10}
  local i
  for (( i=0; i<tries; i++ )); do
    if systemctl is-active --quiet "$VMESS_SERVICE_NAME"; then
      sleep 0.3
      systemctl is-active --quiet "$VMESS_SERVICE_NAME" && return 0
    fi
    sleep 0.5
  done
  return 1
}

service_restart_and_check() {
  systemctl restart "$VMESS_SERVICE_NAME" 2>/tmp/vmess-service-restart.log
  if service_health_check 8; then
    return 0
  fi
  log_err "Service failed to stay active. Recent journal:"
  journalctl -u "$VMESS_SERVICE_NAME" -n 25 --no-pager 2>/dev/null >&2 || true
  return 1
}

service_status_text() {
  systemctl is-active "$VMESS_SERVICE_NAME" 2>/dev/null || echo "inactive"
}

service_logs() {
  local follow=${1:-0}
  if [[ "$follow" == "1" ]]; then
    journalctl -u "$VMESS_SERVICE_NAME" -f --no-pager
  else
    journalctl -u "$VMESS_SERVICE_NAME" -n 100 --no-pager
  fi
}
