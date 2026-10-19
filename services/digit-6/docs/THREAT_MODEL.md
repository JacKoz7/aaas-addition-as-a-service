# Threat Model — `digit-6`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-6` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-19 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-6-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 6); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 6 + 1 becomes something else | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Tampering (request smuggling) | A request whose body length is ambiguous is read differently by the service and a proxy in front of it | A request with both `Content-Length` and `Transfer-Encoding`, another transfer coding or an invalid length answers 400 and closes the connection (RFC 9112, 6.1 and 6.3); there is no proxy in front of the service | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | Many, silent or slow connections, or large heads and bodies, exhaust memory or threads | One thread per connection with a 256 KiB stack, at most 256 connections; a receive silent for 10 s closes the connection; heads above 8 KiB answer 431 and bodies above 64 KiB answer 413 without being read; at most 16 KiB is read while a connection closes. Two clients each opening 256 connections with 1 MB heads, three times, left the service at 10.1 MiB. `mem_limit` and `cpus` bound the damage; an OOM kill stops the container, which has no restart policy, until `make up` | Low |
| Elevation of Privilege | A bug in the HTTP parser is exploited | The parser is Swift code (memory-safe, bounds-checked; unsafe pointers only in the socket and SQLite calls); every line is matched field by field and request bodies are discarded, never interpreted; distroless runtime image without a shell or package manager; non-root user (UID 10001) | Low |
| Tampering (supply chain) | A dependency changes upstream | The package has no dependencies: the build uses the Swift toolchain image and Ubuntu's SQLite package, both pinned, and fetches no package | Low |

No risk is above Low; only High risks are registered in
`docs/governance/RISK_REGISTER.md`.
