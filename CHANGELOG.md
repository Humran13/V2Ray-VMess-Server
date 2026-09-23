# Changelog

## v1.0.0 - 2026-09-23

Initial public release.

- One-command interactive and non-interactive installer for a VMess server
  built on official XTLS/Xray-core (v26.3.27 at release time).
- All seven currently-supported VMess transports: RAW, XHTTP, gRPC,
  WebSocket, HTTPUpgrade, mKCP, and Hysteria transport, with the exact
  transport/security combinations upstream Xray-core supports (see
  `docs/TRANSPORTS.md`).
- Automatic REALITY key generation and target validation; automatic
  Let's Encrypt TLS via certbot, custom certificates, or self-signed
  (testing-only) certificates.
- Full multi-user VMess management (`vmess user add/list/show/enable/
  disable/delete`), client JSON/QR/share-link generation.
- Service management, firewall integration (UFW/firewalld, project-owned
  rules only), diagnostics, backup/restore, safe Xray-core updates with
  automatic rollback, repair, and uninstall (keep-data or purge).
- Supports Ubuntu 18.04 through 26.04 (and newer, with a warning) on
  amd64/x86_64 and arm64/aarch64.
