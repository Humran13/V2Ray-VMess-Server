#!/usr/bin/env bash
# config.sh - installation state + Xray config.json generation/validation/apply.
# Every mutation goes through config_apply(): build -> validate -> swap -> restart
# -> health check -> automatic rollback on failure.

if [[ -n "${VMESS_CONFIG_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_CONFIG_LOADED=1

state_init_default() {
  if [[ ! -f "$VMESS_STATE_FILE" ]]; then
    atomic_write "$VMESS_STATE_FILE" '{
      "transport":"raw","security":"reality","port":443,"domain":"","server_ip":"",
      "listen":"", "ws_path":"/vmess","xhttp_path":"/vmess","httpupgrade_path":"/vmess",
      "grpc_service_name":"vmess-grpc","mkcp_seed":"","hysteria_auth":"",
      "reality":{"private_key":"","public_key":"","short_ids":[],"target":"","server_names":[]},
      "tls":{"mode":"none","cert":"","key":"","domain":"","email":""},
      "xray_version":"","manager_version":"","installed_at":"","owns_xray_binary":false,
      "owns_service":false, "firewall_owned_rules":[]
    }' 0640
  fi
}

state_get() { jq -r "$1" "$VMESS_STATE_FILE"; }
state_get_raw() { jq -c "$1" "$VMESS_STATE_FILE"; }

state_set() { # state_set <jq-filter-lhs-already-in-filter> e.g. '.port = 443'
  local filter=$1 new
  new=$(jq "$filter" "$VMESS_STATE_FILE") || die "Failed to update state (invalid jq filter)."
  atomic_write "$VMESS_STATE_FILE" "$new" 0640
}

state_set_kv() { # state_set_kv <dotted.key> <string-value>
  local new
  new=$(jq --arg v "$2" ".$1 = \$v" "$VMESS_STATE_FILE")
  atomic_write "$VMESS_STATE_FILE" "$new" 0640
}

state_set_num() { # state_set_num <dotted.key> <number>
  local new
  new=$(jq --argjson v "$2" ".$1 = \$v" "$VMESS_STATE_FILE")
  atomic_write "$VMESS_STATE_FILE" "$new" 0640
}

# --- Build streamSettings for a role (server|client) --------------------
config_build_stream_settings() {
  local role=$1
  local transport security path host extra key
  transport=$(state_get '.transport'); security=$(state_get '.security')
  key=$(method_settings_key "$transport")

  case "$transport" in
    xhttp) path=$(state_get '.xhttp_path'); host=$(state_get '.domain') ;;
    websocket) path=$(state_get '.ws_path'); host=$(state_get '.domain') ;;
    httpupgrade) path=$(state_get '.httpupgrade_path'); host=$(state_get '.domain') ;;
    grpc) extra=$(state_get '.grpc_service_name') ;;
    mkcp) extra=$(state_get '.mkcp_seed') ;;
    hysteria) extra=$(state_get '.hysteria_auth') ;;
    *) : ;;
  esac

  local method_settings
  if [[ "$role" == "server" ]]; then
    method_settings=$(build_server_method_settings "$transport" "${path:-}" "${host:-}" "${extra:-}")
  else
    method_settings=$(build_client_method_settings "$transport" "${path:-}" "${host:-}" "${extra:-}")
  fi

  local sec_json
  case "$security" in
    none)
      sec_json='{"security":"none"}'
      ;;
    tls)
      if [[ "$role" == "server" ]]; then
        local cert key_path
        cert=$(state_get '.tls.cert'); key_path=$(state_get '.tls.key')
        sec_json=$(jq -n --arg c "$cert" --arg k "$key_path" --arg sn "$(state_get '.domain')" \
          '{security:"tls", tlsSettings:{serverName:$sn, alpn:["h2","http/1.1"], certificates:[{certificateFile:$c, keyFile:$k}]}}')
      else
        # allowInsecure was removed by upstream Xray-core (runtime rejects the
        # key outright); self-signed TEST certs use pinnedPeerCertSha256
        # instead, computed from the actual cert file. Trusted ACME/custom
        # certs rely on normal CA validation and pin nothing.
        local pin=""
        if [[ "$(state_get '.tls.mode')" == "selfsigned" ]]; then
          pin=$(tls_pinned_sha256 "$(state_get '.tls.cert')")
        fi
        sec_json=$(jq -n --arg sn "$(state_get '.domain')" --arg pin "$pin" \
          '{security:"tls", tlsSettings:({serverName:$sn, alpn:["h2","http/1.1"]} * (if $pin=="" then {} else {pinnedPeerCertSha256:$pin} end))}')
      fi
      ;;
    reality)
      if [[ "$role" == "server" ]]; then
        sec_json=$(jq -n \
          --arg target "$(state_get '.reality.target')" \
          --arg priv "$(state_get '.reality.private_key')" \
          --argjson names "$(state_get_raw '.reality.server_names')" \
          --argjson sids "$(state_get_raw '.reality.short_ids')" \
          '{security:"reality", realitySettings:{show:false, target:$target, serverNames:$names, privateKey:$priv, shortIds:$sids}}')
      else
        sec_json=$(jq -n \
          --arg sn "$(state_get '.reality.server_names[0]')" \
          --arg pub "$(state_get '.reality.public_key')" \
          --arg sid "$(state_get '.reality.short_ids[0]')" \
          '{security:"reality", realitySettings:{serverName:$sn, fingerprint:"chrome", password:$pub, shortId:$sid, spiderX:"/"}}')
      fi
      ;;
  esac

  jq -n --arg method "$transport" --arg key "$key" \
    --argjson methodSettings "$method_settings" --argjson sec "$sec_json" \
    '{method:$method} * {($key): $methodSettings} * $sec'
}

# --- Build full server config.json ---------------------------------------
config_build_server() {
  local port listen transport clients stream
  port=$(state_get '.port')
  listen=$(state_get '.listen')
  clients=$(users_enabled_clients_json)
  stream=$(config_build_stream_settings server)

  local inbound
  inbound=$(jq -n --argjson port "$port" --argjson clients "$clients" --argjson stream "$stream" \
    '{listen: null, port: $port, protocol:"vmess", tag:"vmess-in",
      settings:{clients:$clients, decryption:"none"},
      streamSettings:$stream,
      sniffing:{enabled:true, destOverride:["http","tls"]}}')
  if [[ -n "$listen" && "$listen" != "null" ]]; then
    inbound=$(echo "$inbound" | jq --arg l "$listen" '.listen = $l')
  else
    inbound=$(echo "$inbound" | jq 'del(.listen)')
  fi

  jq -n --argjson inbound "$inbound" --arg logdir "$VMESS_LOG_DIR" '{
    log: {loglevel:"warning", access:($logdir+"/access.log"), error:($logdir+"/error.log")},
    inbounds: [$inbound],
    outbounds: [{protocol:"freedom", tag:"direct"},{protocol:"blackhole", tag:"blocked"}]
  }'
}

# --- Xray config validation using the installed binary --------------------
config_validate_file() {
  local path=$1
  if "$VMESS_XRAY_BIN" run -test -config "$path" >/tmp/vmess-xray-test.log 2>&1; then return 0; fi
  if "$VMESS_XRAY_BIN" -test -config "$path" >/tmp/vmess-xray-test.log 2>&1; then return 0; fi
  return 1
}

# --- Apply: build -> validate -> swap -> restart -> health check -> rollback
config_apply() {
  ensure_dir "$VMESS_STATE_DIR" 0750
  ensure_dir "$VMESS_LOG_DIR" 0750
  local candidate tmp backup_existed=0
  candidate=$(config_build_server)
  tmp=$(mktemp "${VMESS_STATE_DIR}/.candidate.XXXXXX.json")
  printf '%s' "$candidate" > "$tmp"

  if ! config_validate_file "$tmp"; then
    log_err "Candidate Xray configuration failed validation:"
    cat /tmp/vmess-xray-test.log >&2
    rm -f "$tmp"
    return 1
  fi

  if [[ -f "$VMESS_XRAY_CONFIG" ]]; then
    cp -f "$VMESS_XRAY_CONFIG" "${VMESS_XRAY_CONFIG}.bak"
    backup_existed=1
  fi
  mv -f "$tmp" "$VMESS_XRAY_CONFIG"
  chmod 0640 "$VMESS_XRAY_CONFIG"

  if ! service_restart_and_check; then
    log_err "Service failed to come up healthy with the new configuration. Rolling back."
    if [[ "$backup_existed" -eq 1 ]]; then
      mv -f "${VMESS_XRAY_CONFIG}.bak" "$VMESS_XRAY_CONFIG"
      service_restart_and_check || log_err "Rollback restart also failed; manual intervention required."
    fi
    return 1
  fi
  [[ "$backup_existed" -eq 1 ]] && rm -f "${VMESS_XRAY_CONFIG}.bak"
  return 0
}
