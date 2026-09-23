#!/usr/bin/env bash
# run_combo.sh <transport> <security> <port>
# Runs inside a systemd container that already has /opt/work (the repo)
# mounted/copied in. Installs with the given combo, verifies health, and
# runs a real client->server->internet proxy connectivity test.
set -euo pipefail
TRANSPORT=$1; SECURITY=$2; PORT=$3
NAME="ci_${TRANSPORT}_${SECURITY}"

INSTALL_ARGS=(--yes --transport "$TRANSPORT" --security "$SECURITY" --port "$PORT" --user "$NAME")
if [[ "$SECURITY" == "tls" ]]; then
  INSTALL_ARGS+=(--self-signed --domain "test.local")
  grep -q "test.local" /etc/hosts || echo "127.0.0.1 test.local" >> /etc/hosts
fi

echo "=== Installing: VMess + $TRANSPORT + $SECURITY on port $PORT ==="
bash /opt/work/install.sh "${INSTALL_ARGS[@]}"

echo "=== Diagnostics ==="
vmess diagnostics || true

echo "=== Service status ==="
systemctl is-active v2ray-vmess-server

echo "=== Building client config ==="
vmess config "$NAME" > /tmp/client_${TRANSPORT}_${SECURITY}.raw.json
# Client and server run in the same container for this test: point the
# outbound at loopback instead of the (unreachable-from-here) public/domain
# address. Everything else (SNI, REALITY camouflage, TLS settings) is left
# exactly as a real remote client would receive it.
jq '.outbounds[0].settings.vnext[0].address = "127.0.0.1"' \
  /tmp/client_${TRANSPORT}_${SECURITY}.raw.json > /tmp/client_${TRANSPORT}_${SECURITY}.json

echo "=== Validating client config with Xray ==="
xray run -test -config /tmp/client_${TRANSPORT}_${SECURITY}.json

pkill -9 -f "xray run -config /tmp/client_" 2>/dev/null || true
sleep 0.3

CLIENT_SOCKS_PORT=1080
echo "=== Starting client Xray process ==="
nohup xray run -config /tmp/client_${TRANSPORT}_${SECURITY}.json > /tmp/client_${TRANSPORT}_${SECURITY}.log 2>&1 &
CLIENT_PID=$!
trap 'kill -9 "$CLIENT_PID" 2>/dev/null || true' EXIT
sleep 2

echo "=== Real proxy test: curl through SOCKS5 -> VMess -> Xray server -> internet ==="
RESULT=$(curl -x socks5h://127.0.0.1:${CLIENT_SOCKS_PORT} -fsS --max-time 12 https://api.ipify.org || echo "CURL_FAILED")
echo "Result: $RESULT"

kill -9 "$CLIENT_PID" 2>/dev/null || true

if [[ "$RESULT" == "CURL_FAILED" ]]; then
  echo "!!! Real connectivity test FAILED for VMess + $TRANSPORT + $SECURITY"
  cat /tmp/client_${TRANSPORT}_${SECURITY}.log
  exit 1
fi

echo "=== Cleaning up user for next combo ==="
vmess user delete "$NAME" || true

echo "=== PASS: VMess + $TRANSPORT + $SECURITY ==="
