#!/usr/bin/env bash
# transports.sh - the VMess transport/security compatibility matrix and
# shared Xray streamSettings generators (server + client), derived from
# current upstream Xray-core documentation (docs/TRANSPORTS.md has sources).
#
# streamSettings.method values: raw, xhttp, grpc, websocket, httpupgrade, mkcp, hysteria
# streamSettings.security values: none, tls, reality

if [[ -n "${VMESS_TRANSPORTS_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_TRANSPORTS_LOADED=1

TRANSPORT_IDS=(raw xhttp websocket grpc httpupgrade mkcp hysteria)

transport_label() {
  case "$1" in
    raw) echo "RAW" ;;
    xhttp) echo "XHTTP" ;;
    websocket) echo "WebSocket" ;;
    grpc) echo "gRPC" ;;
    httpupgrade) echo "HTTPUpgrade" ;;
    mkcp) echo "mKCP" ;;
    hysteria) echo "Hysteria transport" ;;
    *) echo "$1" ;;
  esac
}

transport_menu_note() {
  case "$1" in
    httpupgrade) echo "Upstream recommends XHTTP as the modern replacement (HTTPUpgrade has a detectable ALPN=http/1.1 fingerprint). Still officially supported." ;;
    mkcp) echo "UDP-based; useful where UDP is unrestricted. Rarely combined with TLS in practice." ;;
    hysteria) echo "QUIC/UDP transport. TLS is mandatory. Distinct from the separate Hysteria2 proxy protocol (not implemented here)." ;;
    *) echo "" ;;
  esac
}

# Returns 0 if <transport>+<security> is a supported combination per current
# upstream Xray-core documentation (docs/config/transport.md compatibility table).
transport_security_supported() {
  local transport=$1 security=$2
  case "$transport" in
    raw|xhttp|grpc)
      case "$security" in none|tls|reality) return 0 ;; *) return 1 ;; esac ;;
    websocket|httpupgrade|mkcp)
      case "$security" in none|tls) return 0 ;; *) return 1 ;; esac ;;
    hysteria)
      case "$security" in tls) return 0 ;; *) return 1 ;; esac ;;
    *) return 1 ;;
  esac
}

# Marks the small set of upstream-recommended defaults. Every officially
# supported combination remains selectable regardless of this marker.
transport_security_recommended() {
  local transport=$1 security=$2
  case "$transport:$security" in
    raw:reality|xhttp:reality|grpc:reality|xhttp:tls) return 0 ;;
    *) return 1 ;;
  esac
}

# Whether a vmess:// share URI can faithfully represent this transport per
# the community VMess AEAD URI convention (net= tcp/kcp/ws/http/grpc).
# XHTTP/HTTPUpgrade/Hysteria are recent additions without a universal URI
# standard: canonical JSON is provided for those instead (see lib/client.sh).
transport_uri_representable() {
  case "$1" in
    raw|websocket|grpc|mkcp) return 0 ;;
    xhttp|httpupgrade|hysteria) return 1 ;;
  esac
}

list_supported_securities() {
  local transport=$1 s
  for s in none tls reality; do
    transport_security_supported "$transport" "$s" && echo "$s"
  done
}

# --- Server-side "<method>Settings" fragment --------------------------
# Args: transport, path, host, extra(seed/serviceName/auth as needed)
build_server_method_settings() {
  local transport=$1 path=${2:-} host=${3:-} extra=${4:-}
  case "$transport" in
    raw)
      jq -n '{acceptProxyProtocol:false, header:{type:"none"}}'
      ;;
    xhttp)
      jq -n --arg path "$path" --arg host "$host" \
        '{path:$path, host:$host, mode:"auto"}'
      ;;
    grpc)
      jq -n --arg svc "$extra" '{serviceName:$svc, multiMode:false}'
      ;;
    websocket)
      jq -n --arg path "$path" --arg host "$host" \
        '{path:$path, host:$host, heartbeatPeriod:0}'
      ;;
    httpupgrade)
      jq -n --arg path "$path" --arg host "$host" \
        '{path:$path, host:$host}'
      ;;
    mkcp)
      # header/seed were removed by upstream Xray-core in favor of FinalMask
      # (see docs/TRANSPORTS.md); plain mKCP with no extra obfuscation layer.
      jq -n '{mtu:1350, tti:20, uplinkCapacity:20, downlinkCapacity:100, cwndMultiplier:1, maxSendingWindow:2097152}'
      ;;
    hysteria)
      jq -n --arg auth "$extra" \
        '{version:2, auth:$auth, udpIdleTimeout:60, masquerade:{type:"", dir:"", url:"", rewriteHost:false, insecure:false, content:"", headers:{}, statusCode:0}}'
      ;;
  esac
}

# --- Client-side "<method>Settings" fragment ---------------------------
build_client_method_settings() {
  local transport=$1 path=${2:-} host=${3:-} extra=${4:-}
  case "$transport" in
    raw)
      jq -n '{header:{type:"none"}}'
      ;;
    xhttp)
      jq -n --arg path "$path" --arg host "$host" \
        '{path:$path, host:$host, mode:"auto"}'
      ;;
    grpc)
      jq -n --arg svc "$extra" '{serviceName:$svc, multiMode:false}'
      ;;
    websocket)
      jq -n --arg path "$path" --arg host "$host" '{path:$path, host:$host}'
      ;;
    httpupgrade)
      jq -n --arg path "$path" --arg host "$host" '{path:$path, host:$host}'
      ;;
    mkcp)
      jq -n '{mtu:1350, tti:20, uplinkCapacity:5, downlinkCapacity:20, cwndMultiplier:1, maxSendingWindow:2097152}'
      ;;
    hysteria)
      jq -n --arg auth "$extra" '{version:2, auth:$auth, udpIdleTimeout:60}'
      ;;
  esac
}

# --- streamSettings.method key name used by the field wrapper ----------
method_settings_key() {
  case "$1" in
    raw) echo "rawSettings" ;;
    xhttp) echo "xhttpSettings" ;;
    grpc) echo "grpcSettings" ;;
    websocket) echo "wsSettings" ;;
    httpupgrade) echo "httpupgradeSettings" ;;
    mkcp) echo "kcpSettings" ;;
    hysteria) echo "hysteriaSettings" ;;
  esac
}

# Whether this transport's network is UDP-based at the OS/firewall level.
transport_is_udp() {
  case "$1" in
    mkcp|hysteria) return 0 ;;
    *) return 1 ;;
  esac
}
