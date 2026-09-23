#!/usr/bin/env bats
setup() {
  source "${BATS_TEST_DIRNAME}/../../lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../../lib/validate.sh"
}

@test "valid_username accepts sane names" {
  valid_username "alice"
  valid_username "user_1-2"
}

@test "valid_username rejects bad input" {
  run valid_username ""
  [ "$status" -ne 0 ]
  run valid_username "../etc/passwd"
  [ "$status" -ne 0 ]
  run valid_username "user with spaces"
  [ "$status" -ne 0 ]
}

@test "valid_uuid accepts a real uuid" {
  valid_uuid "5783a3e7-e373-51cd-8642-c83782b807c5"
}

@test "valid_uuid rejects garbage" {
  run valid_uuid "not-a-uuid"
  [ "$status" -ne 0 ]
  run valid_uuid "5783a3e7e37351cd8642c83782b807c5"
  [ "$status" -ne 0 ]
}

@test "valid_port range checks" {
  valid_port "1"
  valid_port "443"
  valid_port "65535"
  run valid_port "0"
  [ "$status" -ne 0 ]
  run valid_port "65536"
  [ "$status" -ne 0 ]
  run valid_port "abc"
  [ "$status" -ne 0 ]
}

@test "valid_domain accepts real domains" {
  valid_domain "example.com"
  valid_domain "sub.example.co.uk"
  run valid_domain "not a domain"
  [ "$status" -ne 0 ]
  run valid_domain "-bad.com"
  [ "$status" -ne 0 ]
}

@test "valid_ipv4 basic checks" {
  valid_ipv4 "1.2.3.4"
  valid_ipv4 "255.255.255.255"
  run valid_ipv4 "256.1.1.1"
  [ "$status" -ne 0 ]
  run valid_ipv4 "1.2.3"
  [ "$status" -ne 0 ]
}

@test "valid_safe_path blocks traversal and shell metacharacters" {
  valid_safe_path "/etc/v2ray-vmess-server/certs/a.crt"
  run valid_safe_path "/etc/../etc/passwd"
  [ "$status" -ne 0 ]
  run valid_safe_path "relative/path"
  [ "$status" -ne 0 ]
  run valid_safe_path "/tmp/\$(rm -rf /)"
  [ "$status" -ne 0 ]
}

@test "valid_transport enumerates exactly the supported set" {
  for t in raw xhttp grpc websocket httpupgrade mkcp hysteria; do
    valid_transport "$t"
  done
  run valid_transport "quic"
  [ "$status" -ne 0 ]
  run valid_transport "splithttp"
  [ "$status" -ne 0 ]
}
