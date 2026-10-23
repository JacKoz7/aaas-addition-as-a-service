# Threat Model — `digit-7`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-7` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-23 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-7-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 7); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 7 + 1 becomes something else | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Tampering (request smuggling) | A request whose body length is ambiguous is read differently by the service and a proxy in front of it | A request with both `Content-Length` and `Transfer-Encoding`, another transfer coding or an invalid length answers 400 and closes the connection (RFC 9112, 6.1 and 6.3); there is no proxy in front of the service | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | Many, silent or slow connections, or large heads and bodies, exhaust memory or processes | One Erlang process per connection, at most 256 connections (the tracker monitors each, so a crashed connection frees its slot); a receive silent for 10 s closes the connection; a send blocked for 10 s closes it; heads above 8 KiB answer 431 and bodies above 64 KiB answer 413 without being read; at most 16 KiB is read while a connection closes. The flood scenario of CAPACITY.md left the service far below its limit. `mem_limit` and `cpus` bound the damage; an OOM kill stops the container, which has no restart policy, until `make up` | Low |
| Elevation of Privilege | A bug in the HTTP parser is exploited | The parser is Gleam code on the BEAM (memory-safe binaries; the only native code is the esqlite NIF, which receives fixed SQL); every line is matched field by field and request bodies are discarded, never interpreted; minimal Alpine runtime image with only erts, kernel and stdlib of Erlang/OTP; non-root user (UID 10001) | Low |
| Tampering (supply chain) | A dependency changes upstream | Hex packages are locked by version and SHA-256 checksum in `manifest.toml` and verified by `gleam deps download`; the Gleam binary is checked against its release checksum; base images and Alpine packages are pinned (DEPENDENCIES.md) | Low |

No risk is above Low; only High risks are registered in
`docs/governance/RISK_REGISTER.md`.
