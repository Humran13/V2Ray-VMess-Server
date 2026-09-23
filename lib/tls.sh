#!/usr/bin/env bash
# tls.sh - certificate acquisition (ACME/Let's Encrypt), custom certs,
# self-signed test certs, expiry checks, and renewal wiring.

if [[ -n "${VMESS_TLS_LOADED:-}" ]]; then return 0 2>/dev/null || exit 0; fi
VMESS_TLS_LOADED=1

VMESS_ACME_HOOK="/etc/letsencrypt/renewal-hooks/deploy/v2ray-vmess-server.sh"

tls_cert_paths_for_domain() {
  local domain=$1
  echo "/etc/letsencrypt/live/${domain}/fullchain.pem" "/etc/letsencrypt/live/${domain}/privkey.pem"
}

tls_dns_matches_public_ip() {
  local domain=$1 expected_ip=$2 resolved
  resolved=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | sort -u | head -5)
  [[ -z "$resolved" ]] && resolved=$(dig +short "$domain" A 2>/dev/null)
  if [[ -z "$resolved" ]]; then
    log_warn "Could not resolve $domain via DNS."
    return 1
  fi
  if echo "$resolved" | grep -qx "$expected_ip"; then
    return 0
  fi
  log_warn "DNS for $domain resolves to [$resolved], not this server's IP ($expected_ip)."
  return 1
}

tls_port80_free() {
  ! (ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)80$')
}

tls_install_certbot() {
  have_cmd certbot && return 0
  if [[ "$(package_manager)" == "apt" ]]; then
    log_info "Installing certbot for ACME certificate issuance."
    apt_install certbot
  else
    die "certbot is required for automatic TLS but no supported package manager was found."
  fi
}

tls_write_deploy_hook() {
  ensure_dir "$(dirname "$VMESS_ACME_HOOK")" 0755
  atomic_write "$VMESS_ACME_HOOK" \
'#!/usr/bin/env bash
systemctl restart '"$VMESS_SERVICE_NAME"' >/dev/null 2>&1 || true
' 0755
}

# tls_obtain_acme <domain> <email>
# Uses certbot standalone mode. Requires port 80 to be reachable/free.
tls_obtain_acme() {
  local domain=$1 email=$2
  require_valid "$domain" valid_domain "domain"
  tls_install_certbot
  tls_write_deploy_hook

  if [[ -d "/etc/letsencrypt/live/${domain}" ]]; then
    log_info "Existing certificate found for $domain; will renew if needed."
    certbot renew --cert-name "$domain" --deploy-hook "$VMESS_ACME_HOOK" --quiet || \
      log_warn "certbot renew reported an issue; continuing with existing certificate."
    return 0
  fi

  if ! tls_port80_free; then
    die "Port 80 is in use; certbot standalone mode needs it free to obtain a certificate. Free port 80 or provide an existing certificate instead."
  fi

  local email_arg=(--register-unsafely-without-email)
  [[ -n "$email" ]] && email_arg=(-m "$email")

  certbot certonly --standalone --non-interactive --agree-tos \
    "${email_arg[@]}" -d "$domain" \
    --deploy-hook "$VMESS_ACME_HOOK" \
    || die "certbot failed to obtain a certificate for $domain."

  systemctl enable certbot.timer >/dev/null 2>&1 || true
  log_ok "Obtained Let's Encrypt certificate for $domain."
}

# tls_use_custom <cert_path> <key_path> -> copies into state dir with strict perms.
tls_use_custom() {
  local cert=$1 key=$2
  [[ -f "$cert" ]] || die "Certificate file not found: $cert"
  [[ -f "$key" ]] || die "Key file not found: $key"
  openssl x509 -in "$cert" -noout >/dev/null 2>&1 || die "File is not a valid certificate: $cert"
  openssl pkey -in "$key" -noout >/dev/null 2>&1 || die "File is not a valid private key: $key"
  ensure_dir "$VMESS_CERT_DIR" 0750
  atomic_write_file "$cert" "${VMESS_CERT_DIR}/custom.crt" 0644
  atomic_write_file "$key" "${VMESS_CERT_DIR}/custom.key" 0600
  echo "${VMESS_CERT_DIR}/custom.crt" "${VMESS_CERT_DIR}/custom.key"
}

# tls_self_signed <cn> -> generates a clearly-marked testing certificate.
tls_self_signed() {
  local cn=$1
  log_warn "Generating a SELF-SIGNED certificate. This is for TESTING ONLY and is not trusted by real clients."
  ensure_dir "$VMESS_CERT_DIR" 0750
  openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "${VMESS_CERT_DIR}/selfsigned.key" -out "${VMESS_CERT_DIR}/selfsigned.crt" \
    -days 30 -subj "/CN=${cn}" -addext "subjectAltName=DNS:${cn}" >/dev/null 2>&1 \
    || die "Failed to generate self-signed certificate."
  chmod 0600 "${VMESS_CERT_DIR}/selfsigned.key"
  chmod 0644 "${VMESS_CERT_DIR}/selfsigned.crt"
  echo "${VMESS_CERT_DIR}/selfsigned.crt" "${VMESS_CERT_DIR}/selfsigned.key"
}

# tls_check_expiry <cert_path> -> prints "STATUS days" e.g. "PASS 87"
# tls_pinned_sha256 <cert_path> -> lowercase hex SHA-256 fingerprint of the
# leaf certificate, for Xray's pinnedPeerCertSha256 (allowInsecure was
# removed by upstream Xray-core; see docs/TRANSPORTS.md).
tls_pinned_sha256() {
  local cert=$1
  openssl x509 -noout -fingerprint -sha256 -in "$cert" 2>/dev/null \
    | sed -E 's/^.*=//; s/://g' | tr 'A-F' 'a-f'
}

tls_check_expiry() {
  local cert=$1 end_ts now_ts days
  [[ -f "$cert" ]] || { echo "FAIL 0"; return; }
  end_ts=$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | cut -d= -f2)
  [[ -z "$end_ts" ]] && { echo "FAIL 0"; return; }
  end_ts=$(date -d "$end_ts" +%s 2>/dev/null || echo 0)
  now_ts=$(date +%s)
  days=$(( (end_ts - now_ts) / 86400 ))
  if (( days < 0 )); then echo "FAIL $days"
  elif (( days < 14 )); then echo "WARN $days"
  else echo "PASS $days"
  fi
}
