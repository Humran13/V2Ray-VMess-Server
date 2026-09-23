#!/usr/bin/env bash
# validate.sh - strict input validation. All functions return 0 (valid) / 1 (invalid).

if [[ -n "${VMESS_VALIDATE_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_VALIDATE_LOADED=1

valid_username() {
  [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]]
}

valid_uuid() {
  [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_domain() {
  local d=$1
  [[ ${#d} -le 253 ]] && [[ "$d" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

valid_ipv4() {
  local ip=$1 o1 o2 o3 o4
  [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
  for o in "$o1" "$o2" "$o3" "$o4"; do (( o <= 255 )) || return 1; done
  return 0
}

valid_ipv6() {
  [[ "$1" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]] || [[ "$1" == "::" ]]
}

valid_host() {
  valid_domain "$1" || valid_ipv4 "$1" || valid_ipv6 "$1"
}

# Safe path: absolute, no shell metacharacters, no ".." traversal.
valid_safe_path() {
  local p=$1
  [[ "$p" == /* ]] || return 1
  [[ "$p" != *".."* ]] || return 1
  [[ "$p" =~ ^[a-zA-Z0-9/_.,:@-]+$ ]] || return 1
  return 0
}

valid_transport() {
  case "$1" in
    raw|xhttp|grpc|websocket|httpupgrade|mkcp|hysteria) return 0 ;;
    *) return 1 ;;
  esac
}

valid_security() {
  case "$1" in
    none|tls|reality) return 0 ;;
    *) return 1 ;;
  esac
}

valid_ws_path() {
  [[ "$1" =~ ^/[a-zA-Z0-9/_-]{0,120}$ ]]
}

valid_service_name() {
  [[ "$1" =~ ^[a-zA-Z0-9_.-]{1,64}$ ]]
}

require_valid() { # require_valid <value> <validator_fn> <label>
  local val=$1 fn=$2 label=$3
  if ! "$fn" "$val"; then
    die "Invalid $label: '$val'"
  fi
}
