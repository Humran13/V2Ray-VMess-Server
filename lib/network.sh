#!/usr/bin/env bash
# network.sh - public IP discovery, port conflict/validity checks, connectivity.

if [[ -n "${VMESS_NETWORK_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_NETWORK_LOADED=1

detect_public_ipv4() {
  local ip
  for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
    ip=$(curl -fsSL4 --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
    valid_ipv4 "$ip" && { echo "$ip"; return 0; }
  done
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  valid_ipv4 "$ip" && { echo "$ip"; return 0; }
  return 1
}

detect_public_ipv6() {
  local ip
  ip=$(curl -fsSL6 --max-time 4 "https://api64.ipify.org" 2>/dev/null | tr -d '[:space:]')
  valid_ipv6 "$ip" && { echo "$ip"; return 0; }
  return 1
}

has_ipv6() {
  [[ -n "$(detect_public_ipv6)" ]] || ip -6 addr show scope global 2>/dev/null | grep -q inet6
}

check_internet() {
  curl -fsSL --max-time 6 -o /dev/null "https://github.com" 2>/dev/null
}

port_in_use() { # port_in_use <port> [tcp|udp]
  local port=$1 proto=${2:-tcp}
  if have_cmd ss; then
    if [[ "$proto" == "udp" ]]; then
      ss -lun 2>/dev/null | awk '{print $5}' | grep -qE "[:.]${port}\$"
    else
      ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}\$"
    fi
  else
    return 1
  fi
}

dns_resolves_to() {
  local domain=$1 ip=$2
  tls_dns_matches_public_ip "$domain" "$ip"
}
