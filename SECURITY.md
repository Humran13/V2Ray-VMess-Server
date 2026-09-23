# Security Policy

## Reporting a Vulnerability

If you find a security issue in this installer/manager (not in Xray-core
itself), please open a private report via GitHub's "Report a vulnerability"
feature on this repository, or open an issue without exploit details and we
will follow up for a private channel.

For vulnerabilities in the Xray-core engine itself, report them upstream to
[XTLS/Xray-core](https://github.com/XTLS/Xray-core/security).

## Scope

This project is an installer and management layer around the official
XTLS/Xray-core binary. It does not implement its own VMess protocol,
run a web control panel, collect telemetry, or expose any network-facing
management API. Security-relevant behavior in scope includes:

- Input validation and shell-injection safety in `install.sh`, `bin/vmess`,
  and `lib/*.sh`.
- Safe handling of REALITY private keys, TLS private keys, and user UUIDs.
- Firewall rule management (only opening what is required, only removing
  rules this project created).
- Safe, validated configuration changes with automatic rollback.

## Supported Versions

Only the latest tagged release is supported with security fixes.
