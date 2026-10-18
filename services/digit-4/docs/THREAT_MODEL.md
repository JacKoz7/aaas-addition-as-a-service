# Threat Model — `digit-4`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-4` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-4-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 4); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 4 + 1 becomes something else | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Tampering (request smuggling) | A request whose body length is ambiguous is read differently by the service and a proxy in front of it | A request with both `Content-Length` and `Transfer-Encoding`, another transfer coding or an invalid length answers 400 and closes the connection (RFC 9112, 6.1 and 6.3); there is no proxy in front of the service | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | Many, silent or slow connections, or large heads and bodies, exhaust memory | Each connection is a coroutine (a few KiB), so a slow client delays only itself; at most 256 connections at once; a connection silent for 10 s is closed; heads above 8 KiB answer 431, bodies above 64 KiB answer 413 without being read; `mem_limit` 128 MB and `cpus` bound the damage; the network is internal and the edge is rate limited (P6.2) | Low |
| Elevation of Privilege | A bug in the HTTP parser is exploited | The parser is Lua code (memory-safe; no pointer arithmetic), every field is matched by an anchored pattern and request bodies are discarded, never interpreted; the C modules are distribution packages (cqueues, lsqlite3, luaposix); non-root user (UID 10001) | Low |
| Tampering (supply chain) | A module of the runtime image changes upstream | Every Alpine package is pinned to its exact version in the Dockerfile; the image is rebuilt only by `make build-digit-4` | Low |

No risk is above Low; only High risks are registered in
`docs/governance/RISK_REGISTER.md`.
