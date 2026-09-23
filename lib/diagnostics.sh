#!/usr/bin/env bash
# diagnostics.sh - PASS/WARN/FAIL health checks. Never prints private keys.

if [[ -n "${VMESS_DIAGNOSTICS_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_DIAGNOSTICS_LOADED=1

_diag() { # _diag <STATUS> <message>
  local status=$1; shift
  local color=$C_GRN
  if [[ "$status" == "WARN" ]]; then color=$C_YEL; DIAG_WARNS=$((DIAG_WARNS+1))
  elif [[ "$status" == "FAIL" ]]; then color=$C_RED; DIAG_FAILS=$((DIAG_FAILS+1))
  fi
  printf '%s[%-4s]%s %s\n' "$color" "$status" "$C_RST" "$*"
  return 0
}

run_diagnostics() {
  DIAG_FAILS=0; DIAG_WARNS=0
  detect_os; detect_arch

  _diag PASS "OS: ${OS_ID} ${OS_VERSION_ID} (${OS_CODENAME})"
  _diag PASS "Architecture: ${OS_ARCH}"

  if [[ -x "$VMESS_XRAY_BIN" ]]; then
    _diag PASS "Xray binary present: $(xray_version)"
  else
    _diag FAIL "Xray binary not found at $VMESS_XRAY_BIN"
  fi
  _diag PASS "Manager version: $(manager_version)"

  if [[ -f "$VMESS_XRAY_CONFIG" ]]; then
    if config_validate_file "$VMESS_XRAY_CONFIG"; then
      _diag PASS "Xray configuration is valid"
    else
      _diag FAIL "Xray configuration failed validation"
    fi
  else
    _diag FAIL "No Xray configuration found at $VMESS_XRAY_CONFIG"
  fi

  local svc; svc=$(service_status_text)
  if [[ "$svc" == "active" ]]; then _diag PASS "Service ${VMESS_SERVICE_NAME}: active"
  else _diag FAIL "Service ${VMESS_SERVICE_NAME}: ${svc}"; fi

  local tstatus; tstatus=$(check_time_sync)
  if [[ "${tstatus##*:}" == "yes" ]]; then _diag PASS "Time synchronization: OK (${tstatus%%:*})"
  else _diag WARN "Time synchronization: NOT confirmed synced (VMess requires accurate clocks)"; fi

  if [[ -f "$VMESS_STATE_FILE" ]]; then
    local transport security port
    transport=$(state_get '.transport'); security=$(state_get '.security'); port=$(state_get '.port')
    _diag PASS "Selected mode: VMess + $(transport_label "$transport") + ${security}"
    if port_in_use "$port" "$( transport_is_udp "$transport" && echo udp || echo tcp )"; then
      _diag PASS "Configured port $port is listening"
    else
      _diag WARN "Configured port $port does not appear to be listening"
    fi

    if [[ "$security" == "tls" ]]; then
      local cert result
      cert=$(state_get '.tls.cert')
      if [[ -f "$cert" ]]; then
        result=$(tls_check_expiry "$cert")
        _diag "${result%% *}" "TLS certificate expiry: ${result##* } days remaining"
      else
        _diag FAIL "TLS certificate file missing: $cert"
      fi
    fi
    if [[ "$security" == "reality" ]]; then
      local target; target=$(state_get '.reality.target')
      if [[ -n "$target" && "$target" != "null" ]]; then
        _diag PASS "REALITY target configured: $target"
      else
        _diag FAIL "REALITY target not configured"
      fi
    fi
  fi

  if detect_public_ipv4 >/dev/null 2>&1; then _diag PASS "IPv4 reachability: OK"
  else _diag WARN "Could not determine public IPv4 address"; fi
  if has_ipv6; then _diag PASS "IPv6: available"; else _diag WARN "IPv6: not available (IPv4-only host)"; fi

  if check_internet; then _diag PASS "Internet/GitHub reachability: OK"
  else _diag WARN "Could not reach github.com (outbound connectivity issue?)"; fi

  local fwb; fwb=$(firewall_backend)
  _diag PASS "Firewall backend: ${fwb}"

  if [[ -d "$VMESS_STATE_DIR" ]]; then
    local perms; perms=$(stat -c '%a' "$VMESS_STATE_DIR" 2>/dev/null)
    if [[ "$perms" == "750" || "$perms" == "700" ]]; then _diag PASS "State directory permissions: $perms"
    else _diag WARN "State directory permissions are $perms (expected 750)"; fi
  fi

  echo
  if (( DIAG_FAILS > 0 )); then
    log_err "Diagnostics: ${DIAG_FAILS} failure(s), ${DIAG_WARNS} warning(s)."
    return 1
  elif (( DIAG_WARNS > 0 )); then
    log_warn "Diagnostics: 0 failures, ${DIAG_WARNS} warning(s)."
    return 0
  else
    log_ok "Diagnostics: all checks passed."
    return 0
  fi
}
