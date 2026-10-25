# Threat Model — `digit-9`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-9` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-25 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-9-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 9); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 9 + 1 no longer carries | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Tampering (request smuggling) | A request whose body length is ambiguous is read differently by the service and a proxy in front of it | A request with both `Content-Length` and `Transfer-Encoding`, another transfer coding or an invalid length answers 400 and closes the connection (RFC 9112, 6.1 and 6.3); there is no proxy in front of the service | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | Many, silent or slow connections, or large heads and bodies, exhaust memory | One Racket thread per connection, at most 256 connections, one input buffer of 4 to 16 KiB per connection; a receive silent for 10 s closes the connection; heads above 8 KiB answer 431 and bodies above 64 KiB answer 413 without being read; at most 16 KiB is read while a connection closes. The memory guard runs a major garbage collection whenever the memory the runtime holds grows 12 MiB, so freed memory goes back to the system during a burst. Two clients each opening 256 connections with 1 MB heads, ten rounds, peaked at 86.1 MiB of 128 MiB and left the service at 70 MiB (CAPACITY.md). `mem_limit` and `cpus` bound the damage; an OOM kill stops the container, which has no restart policy, until `make up` | Low |
| Elevation of Privilege | A bug in the HTTP parser is exploited | The parser is Racket code: memory-safe, with checked indices on every byte and string access; unsafe code is limited to the foreign calls of `sqlite.rkt`, which pass only SQL text written in the code and the migration file names; every line is matched field by field and request bodies are discarded, never interpreted; minimal Alpine runtime image without the Racket package manager or compiler; non-root user (UID 10001) | Low |
| Tampering (supply chain) | A dependency changes upstream | The runtime image holds the executable built by `raco exe`, the Racket runtime from Alpine's pinned `racket` package and pinned Alpine libraries. The packages of the lint, test and documentation stages come from the catalog of the Racket 9.2 release and, for fmt, pretty-expressive and review, from pinned Git commits; they never reach the runtime image | Low |

No risk is above Low; only High risks are registered in
`docs/governance/RISK_REGISTER.md`.
