#!/usr/bin/env bash
# reality.sh - REALITY key material generation and target validation.
# REALITY is only valid with the raw, xhttp, and grpc transport methods
# (see docs/TRANSPORTS.md and lib/transports.sh::transport_security_supported).

if [[ -n "${VMESS_REALITY_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_REALITY_LOADED=1

REALITY_DEFAULT_TARGETS=("swift.com:443" "www.microsoft.com:443" "www.bing.com:443" "itunes.apple.com:443")

# Generates an X25519 keypair using the installed xray binary.
# Prints "private_key public_key" (public key == REALITY "password").
reality_generate_keypair() {
  local out priv pub
  out=$("$VMESS_XRAY_BIN" x25519 2>/dev/null) || die "Failed to run 'xray x25519' to generate REALITY keys."
  priv=$(echo "$out" | grep -iE '^(Private ?key|PrivateKey)' | head -1 | sed -E 's/^[^:]+:\s*//')
  pub=$(echo "$out" | grep -iE '^(Public ?key|Password)' | head -1 | sed -E 's/^[^:]+:\s*//')
  [[ -z "$priv" ]] && die "Could not parse private key from 'xray x25519' output."
  if [[ -z "$pub" ]]; then
    out=$("$VMESS_XRAY_BIN" x25519 -i "$priv" 2>/dev/null)
    pub=$(echo "$out" | grep -iE '^(Public ?key|Password)' | head -1 | sed -E 's/^[^:]+:\s*//')
  fi
  [[ -z "$pub" ]] && die "Could not derive REALITY public key."
  echo "$priv $pub"
}

reality_generate_short_id() {
  openssl rand -hex 8
}

# reality_validate_target <host:port> -> 0 if usable, prints warnings.
reality_validate_target() {
  local hp=$1 host port
  host=${hp%:*}; port=${hp##*:}
  [[ "$hp" == *:* ]] || { log_err "REALITY target must be host:port (e.g. www.microsoft.com:443)"; return 1; }
  valid_port "$port" || { log_err "Invalid REALITY target port: $port"; return 1; }

  case "$host" in
    localhost|127.*|10.*|172.16.*|172.17.*|172.18.*|172.19.*|172.2[0-9].*|172.3[01].*|192.168.*|169.254.*|::1|0.0.0.0)
      log_err "REALITY target must be a public, real-world website, not a private/loopback address."
      return 1
      ;;
  esac
  valid_host "$host" || { log_err "Invalid REALITY target host: $host"; return 1; }

  if have_cmd openssl; then
    local probe
    probe=$(timeout 6 openssl s_client -connect "$hp" -servername "$host" -alpn h2,http/1.1 </dev/null 2>/dev/null)
    if [[ -z "$probe" ]]; then
      log_warn "Could not verify TLS handshake with $hp from this server. It may still work, but verify connectivity before relying on it."
    elif ! echo "$probe" | grep -q "TLSv1.3"; then
      log_warn "$hp did not negotiate TLS 1.3 in this probe. REALITY works best against TLS 1.3 targets."
    else
      log_ok "Verified TLS 1.3 handshake with REALITY target $hp."
    fi
  fi
  return 0
}

reality_pick_default_target() {
  echo "${REALITY_DEFAULT_TARGETS[0]}"
}
