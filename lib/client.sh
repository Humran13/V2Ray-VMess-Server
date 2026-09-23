#!/usr/bin/env bash
# client.sh - per-user client configuration: canonical Xray JSON, vmess://
# share links (only where the community URI schema can represent the
# transport faithfully), and terminal QR codes.

if [[ -n "${VMESS_CLIENT_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_CLIENT_LOADED=1

client_server_address() {
  local domain
  domain=$(state_get '.domain')
  if [[ -n "$domain" && "$domain" != "null" ]]; then echo "$domain"; else state_get '.server_ip'; fi
}

# Full standalone client Xray config.json: local SOCKS/HTTP proxy -> VMess outbound.
client_build_config_json() {
  local name=$1 uuid transport security addr port stream outbound
  uuid=$(users_get_uuid "$name")
  [[ -z "$uuid" || "$uuid" == "null" ]] && die "No such user: $name"
  transport=$(state_get '.transport'); security=$(state_get '.security')
  addr=$(client_server_address); port=$(state_get '.port')
  stream=$(config_build_stream_settings client)

  outbound=$(jq -n --arg addr "$addr" --argjson port "$port" --arg uuid "$uuid" --argjson stream "$stream" \
    '{protocol:"vmess", tag:"proxy",
      settings:{vnext:[{address:$addr, port:$port, users:[{id:$uuid, alterId:0, security:"auto"}]}]},
      streamSettings:$stream}')

  jq -n --argjson outbound "$outbound" '{
    log:{loglevel:"warning"},
    inbounds:[
      {listen:"127.0.0.1", port:1080, protocol:"socks", settings:{udp:true}},
      {listen:"127.0.0.1", port:1081, protocol:"http"}
    ],
    outbounds:[$outbound, {protocol:"freedom", tag:"direct"}]
  }'
}

# vmess:// share URI, or empty string if this transport is not faithfully
# representable in the community VMess AEAD URI schema.
client_build_uri() {
  local name=$1 uuid transport security addr port remark payload
  transport=$(state_get '.transport'); security=$(state_get '.security')
  if ! transport_uri_representable "$transport"; then
    echo ""
    return 0
  fi
  uuid=$(users_get_uuid "$name")
  addr=$(client_server_address); port=$(state_get '.port')
  remark="V2Ray-VMess-${name}"

  local net type path host tls sni alpn fp pbk sid spx
  tls=""; sni=""; alpn=""; fp=""; pbk=""; sid=""; spx=""
  case "$security" in
    tls) tls="tls"; sni=$(state_get '.domain'); alpn="h2,http/1.1" ;;
    reality)
      tls="reality"; fp="chrome"
      sni=$(state_get '.reality.server_names[0]')
      pbk=$(state_get '.reality.public_key')
      sid=$(state_get '.reality.short_ids[0]')
      spx="/"
      ;;
  esac

  case "$transport" in
    raw) net="tcp"; type="none"; path=""; host="" ;;
    websocket) net="ws"; type="none"; path=$(state_get '.ws_path'); host=$(state_get '.domain') ;;
    grpc) net="grpc"; type="gun"; path=$(state_get '.grpc_service_name'); host="" ;;
    mkcp) net="kcp"; type="none"; path=""; host="" ;;
  esac

  payload=$(jq -n \
    --arg v "2" --arg ps "$remark" --arg add "$addr" --arg port "$port" --arg id "$uuid" \
    --arg aid "0" --arg scy "auto" --arg net "$net" --arg type "$type" --arg host "$host" \
    --arg path "$path" --arg tls "$tls" --arg sni "$sni" --arg alpn "$alpn" --arg fp "$fp" \
    --arg pbk "$pbk" --arg sid "$sid" --arg spx "$spx" \
    '{v:$v, ps:$ps, add:$add, port:$port, id:$id, aid:$aid, scy:$scy, net:$net, type:$type,
      host:$host, path:$path, tls:$tls, sni:$sni, alpn:$alpn, fp:$fp, pbk:$pbk, sid:$sid, spx:$spx}')

  echo "vmess://$(printf '%s' "$payload" | base64 -w0)"
}

client_uri_caveat() {
  local transport=$1
  case "$transport" in
    xhttp) echo "XHTTP has no universally standardized vmess:// URI field yet across clients. Import the canonical JSON below in an Xray-core-based client instead." ;;
    httpupgrade) echo "HTTPUpgrade has no universally standardized vmess:// URI field. Use the canonical JSON below." ;;
    hysteria) echo "VMess-over-Hysteria has no vmess:// URI representation. Use the canonical JSON below in an Xray-core-based client." ;;
    *) echo "" ;;
  esac
}

client_qr_render() {
  local data=$1
  if have_cmd qrencode; then
    qrencode -t ANSIUTF8 "$data"
  else
    log_warn "qrencode not installed; skipping QR rendering. Install with: apt-get install -y qrencode"
  fi
}
