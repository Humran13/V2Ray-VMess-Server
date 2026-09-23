# VMess Transport / Security Compatibility Matrix

Derived directly from current upstream Xray-core documentation
(`XTLS/Xray-docs-next`, `docs/en/config/transport.md` and
`docs/en/config/transports/*.md`) and confirmed empirically against
Xray-core **v26.3.27** in `tests/integration/`. If a newer Xray-core release
changes this matrix, upstream source/runtime behavior wins over stale docs —
update `lib/transports.sh` and this file together.

## Transport methods (`streamSettings.method`)

| Method | VMess supported | `none` | `tls` | `reality` | Notes |
|---|---|---|---|---|---|
| `raw` (formerly `tcp`) | Yes | Yes | Yes | Yes | Optional HTTP header obfuscation (`rawSettings.header.type=http`) still supported. |
| `xhttp` | Yes | Yes | Yes | Yes | Modern replacement for HTTPUpgrade/SplitHTTP. |
| `grpc` | Yes | Yes | Yes | Yes | |
| `websocket` | Yes | Yes | Yes | No | |
| `httpupgrade` | Yes | Yes | Yes | No | Upstream recommends migrating to XHTTP (detectable `ALPN=http/1.1` fingerprint), but it remains officially supported. |
| `mkcp` | Yes | Yes | Yes | No | UDP-based. `header`/`seed` fields were **removed** by upstream in favor of `FinalMask`; this project ships plain mKCP with no extra obfuscation layer. |
| `hysteria` | Yes | No | **Required** | No | QUIC/UDP transport. Distinct from the separate Hysteria2 *proxy protocol* (not implemented here — this is VMess running over Xray's Hysteria *stream transport*). |

REALITY is explicitly documented as compatible with **only** `raw`, `xhttp`,
and `grpc`. This project's `transport_security_supported()` in
`lib/transports.sh` encodes exactly this table and is covered by
`tests/unit/transports.bats`.

## Runtime-vs-docs discrepancies found and handled

- **`allowInsecure` was removed** from `tlsSettings` in current Xray-core
  (runtime error: *"The feature allowInsecure has been removed and migrated
  to pinnedPeerCertSha256"*), even though some docs snapshots still list it.
  This project never emits `allowInsecure`; self-signed **testing** certs use
  `pinnedPeerCertSha256` (computed from the actual cert) instead.
- **mKCP `header`/`seed` were removed**, migrated to `FinalMask`. This
  project ships mKCP with sane `mtu`/`tti`/window defaults and no
  `FinalMask` obfuscation layer (a plain, valid, currently-supported mKCP
  configuration).
- `streamSettings` now uses `method` (not the older `network` key) as the
  field name for selecting the transport in the Xray-core config schema.

## VMess share-link (`vmess://`) representability

The community VMess AEAD URI schema (`net=tcp|ws|grpc|kcp|...`) predates
XHTTP, HTTPUpgrade, and the Hysteria transport, and there is no universally
agreed encoding for them across clients. To avoid producing a link that only
works in some clients and silently fails in others, this project:

- Generates a `vmess://` link for **raw, websocket, grpc, mkcp**.
- For **xhttp, httpupgrade, hysteria**, prints the canonical Xray-core client
  JSON instead, with an explicit note — the config is exact and correct, it
  just isn't expressed as a legacy share link.

## Real end-to-end testing performed

Every row in the compatibility table above (16 valid transport/security
combinations) was tested in `tests/integration/run_combo.sh`: real install,
real Xray-core server + real Xray-core client processes, actual VMess
handshake, and a live proxied HTTPS request to the public internet through
the tunnel. See the CI integration workflow for the full matrix across the
Ubuntu OS versions this project supports.
