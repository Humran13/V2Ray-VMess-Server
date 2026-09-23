# V2Ray VMess Server

A production-ready installer and management system for a VMess server, built
on the official [XTLS/Xray-core](https://github.com/XTLS/Xray-core) engine.
This project does not implement its own VMess protocol — it installs,
configures, secures, and manages the official Xray-core binary for you.

## Features

- One-command install, interactive or fully non-interactive/scriptable.
- Every currently-supported VMess transport: **RAW, XHTTP, gRPC, WebSocket,
  HTTPUpgrade, mKCP, Hysteria** — with only the transport/security
  combinations upstream Xray-core actually supports (see
  [`docs/TRANSPORTS.md`](docs/TRANSPORTS.md)).
- Automatic REALITY key generation, or automatic Let's Encrypt TLS, custom
  certificates, or self-signed (testing-only) certificates.
- Full multi-user management, client JSON/QR/share-link generation.
- Service management, firewall integration, diagnostics, backup/restore,
  safe updates with automatic rollback, repair, and clean uninstall.

## Supported platforms

- **Ubuntu**: 18.04, 20.04, 22.04, 24.04, 26.04 LTS (newer releases continue
  with a warning via feature detection rather than being rejected).
- **Architecture**: amd64/x86_64 and arm64/aarch64.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Humran13/V2Ray-VMess-Server/main/install.sh | sudo bash
```

This runs the interactive wizard: pick a transport, a security mode, a port,
and a domain (if using TLS), and the installer handles Xray-core
installation, configuration, validation, firewall rules, and the first user.

### Non-interactive install

```bash
curl -fsSL https://raw.githubusercontent.com/Humran13/V2Ray-VMess-Server/main/install.sh | \
  sudo bash -s -- --yes --transport raw --security reality --port 443 --user alice
```

Key flags: `--transport`, `--security`, `--port`, `--domain`, `--email`,
`--cert`/`--key`, `--reality-target`, `--self-signed`, `--user`, `--yes`.
Run `install.sh --help` for the full list.

Interactive prompts read from `/dev/tty`, so this works correctly even when
piped through `curl | sudo bash`.

## Managing the server

After install, use the `vmess` command:

```
sudo vmess                 # interactive menu
sudo vmess status
sudo vmess user add alice
sudo vmess user list
sudo vmess qr alice
sudo vmess link alice
sudo vmess config alice
sudo vmess diagnostics
sudo vmess backup
sudo vmess restore <file>
sudo vmess update
sudo vmess repair
sudo vmess uninstall [--purge]
```

## Client setup

- `sudo vmess link <name>` prints a `vmess://` share link for transports the
  community URI schema can represent faithfully (RAW, WebSocket, gRPC,
  mKCP).
- `sudo vmess qr <name>` renders that link as a terminal QR code.
- `sudo vmess config <name>` prints the canonical Xray-core client JSON for
  **any** transport, including XHTTP, HTTPUpgrade, and Hysteria, which don't
  have a universally standardized share-link encoding yet — import this JSON
  directly into an Xray-core-based client.

## TLS and REALITY

- **TLS**: automatic Let's Encrypt (via certbot, requires a domain pointing
  at the server and port 80 reachable), an existing certificate/key pair, or
  a self-signed certificate for local testing only (never used by default).
- **REALITY**: X25519 keys and a short ID are generated automatically; you
  can accept a sensible default camouflage target or provide your own
  (`--reality-target host:port`), which is validated before use.

## Ports and firewall

The installer opens only the port(s) it needs (TCP or UDP, depending on
transport) via UFW or firewalld if one is active, and tracks exactly which
rules it created so `uninstall` removes only its own rules — it never
flushes or disables your firewall.

## Updates, backup, and uninstall

- `sudo vmess update` checks the latest **stable** Xray-core release, backs
  up first, validates the new binary against your existing config, and
  automatically rolls back if the service doesn't come up healthy.
- `sudo vmess backup` / `sudo vmess restore <file>` create/restore
  timestamped, path-traversal-safe archives of your configuration and users.
- `sudo vmess uninstall` removes the program but keeps your config/backups;
  `sudo vmess uninstall --purge` removes everything this project owns. An
  Xray binary that pre-existed before this installer is never removed.

## Troubleshooting

Run `sudo vmess diagnostics` for a PASS/WARN/FAIL health report covering OS,
architecture, Xray version/config validity, service status, time
synchronization (VMess requires an accurate clock), listening port, TLS
certificate expiry, REALITY configuration, firewall state, and connectivity.

## Security notes

- No web control panel, no telemetry, no default shared UUID — every user
  gets a freshly generated UUID.
- Configuration changes are always validated with the real Xray-core binary
  before being applied, and automatically rolled back if the service fails
  to come up healthy.
- Self-signed certificates are clearly marked testing-only and never used
  silently in a production path.

## Limitations

- The vmess:// share-link format has no ratified standard for XHTTP,
  HTTPUpgrade, or the Hysteria transport across all clients; those modes
  ship canonical JSON instead of a link (see
  [`docs/TRANSPORTS.md`](docs/TRANSPORTS.md)).
- REALITY's camouflage `target` must be a real, reachable TLS 1.3 site;
  reachability from your specific network/hosting provider can vary, so the
  installer probes and validates it before finishing.

## Attribution

This project packages and manages
[XTLS/Xray-core](https://github.com/XTLS/Xray-core); all credit for the
VMess/VLESS/REALITY protocol implementation belongs to the XTLS project and
its contributors.

## License

[MIT](LICENSE)
