#!/usr/bin/env bats
# Locks in the current upstream Xray-core compatibility matrix
# (see docs/TRANSPORTS.md for sources). If this test starts failing after
# an Xray-core release, upstream behavior has changed and the matrix in
# lib/transports.sh must be updated to match, not the test.

setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/validate.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/transports.sh"
}

@test "REALITY is only supported on raw, xhttp, grpc" {
  transport_security_supported raw reality
  transport_security_supported xhttp reality
  transport_security_supported grpc reality
  run transport_security_supported websocket reality
  [ "$status" -ne 0 ]
  run transport_security_supported httpupgrade reality
  [ "$status" -ne 0 ]
  run transport_security_supported mkcp reality
  [ "$status" -ne 0 ]
  run transport_security_supported hysteria reality
  [ "$status" -ne 0 ]
}

@test "hysteria requires TLS and rejects none/reality" {
  transport_security_supported hysteria tls
  run transport_security_supported hysteria none
  [ "$status" -ne 0 ]
  run transport_security_supported hysteria reality
  [ "$status" -ne 0 ]
}

@test "raw, xhttp, grpc, websocket, httpupgrade, mkcp all support none and tls" {
  for t in raw xhttp grpc websocket httpupgrade mkcp; do
    transport_security_supported "$t" none
    transport_security_supported "$t" tls
  done
}

@test "every transport id has a human label" {
  for t in "${TRANSPORT_IDS[@]}"; do
    label=$(transport_label "$t")
    [ -n "$label" ]
  done
}

@test "URI representability matches documented client-compatibility caveats" {
  transport_uri_representable raw
  transport_uri_representable websocket
  transport_uri_representable grpc
  transport_uri_representable mkcp
  run transport_uri_representable xhttp
  [ "$status" -ne 0 ]
  run transport_uri_representable httpupgrade
  [ "$status" -ne 0 ]
  run transport_uri_representable hysteria
  [ "$status" -ne 0 ]
}

@test "method_settings_key maps every transport" {
  for t in "${TRANSPORT_IDS[@]}"; do
    key=$(method_settings_key "$t")
    [ -n "$key" ]
  done
}
