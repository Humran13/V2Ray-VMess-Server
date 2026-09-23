#!/usr/bin/env bats
# Verifies generated streamSettings JSON is well-formed and structurally
# correct for every officially supported transport/security combination.
# (Actual Xray-core validation of full configs happens in tests/integration.)

setup() {
  export VMESS_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$VMESS_STATE_DIR"
  source "${BATS_TEST_DIRNAME}/../../lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/validate.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/transports.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/config.sh"
  state_init_default
}

combos() {
  cat <<'EOF'
raw none
raw tls
raw reality
xhttp none
xhttp tls
xhttp reality
grpc none
grpc tls
grpc reality
websocket none
websocket tls
httpupgrade none
httpupgrade tls
mkcp none
mkcp tls
hysteria tls
EOF
}

@test "every documented transport/security combo produces valid JSON for both roles" {
  while read -r transport security; do
    [ -z "$transport" ] && continue
    new=$(jq --arg t "$transport" --arg s "$security" '.transport=$t | .security=$s | .domain="example.com" | .reality.target="www.microsoft.com:443" | .reality.server_names=["www.microsoft.com"] | .reality.private_key="priv" | .reality.public_key="pub" | .reality.short_ids=["aabbccdd"] | .tls.cert="/tmp/c.pem" | .tls.key="/tmp/k.pem" | .grpc_service_name="svc" | .mkcp_seed="seed" | .hysteria_auth="auth"' "$VMESS_STATE_FILE")
    echo "$new" > "$VMESS_STATE_FILE"

    server_json=$(config_build_stream_settings server)
    echo "$server_json" | jq -e . >/dev/null

    client_json=$(config_build_stream_settings client)
    echo "$client_json" | jq -e . >/dev/null

    method=$(echo "$server_json" | jq -r '.method')
    [ "$method" == "$transport" ]
  done < <(combos)
}

@test "config_build_server produces a single vmess inbound with a port and clients array" {
  echo '{"users":[{"name":"u1","uuid":"5783a3e7-e373-51cd-8642-c83782b807c5","enabled":true,"created":"2026-01-01T00:00:00Z"}]}' > "${VMESS_STATE_DIR}/users.json"
  export VMESS_USERS_FILE="${VMESS_STATE_DIR}/users.json"
  source "${BATS_TEST_DIRNAME}/../../lib/users.sh"

  new=$(jq '.transport="raw" | .security="none" | .port=8443' "$VMESS_STATE_FILE")
  echo "$new" > "$VMESS_STATE_FILE"

  cfg=$(config_build_server)
  echo "$cfg" | jq -e . >/dev/null
  [ "$(echo "$cfg" | jq -r '.inbounds[0].protocol')" == "vmess" ]
  [ "$(echo "$cfg" | jq -r '.inbounds[0].port')" == "8443" ]
  [ "$(echo "$cfg" | jq -r '.inbounds[0].settings.clients[0].id')" == "5783a3e7-e373-51cd-8642-c83782b807c5" ]
}
