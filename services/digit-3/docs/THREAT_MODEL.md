# Threat Model — `digit-3`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-3` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-3-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 3); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 3 + 1 becomes something else | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | Many connections, silent connections or large bodies exhaust threads or memory (one thread per connection) | Each read from a connection times out after 2 s; bodies above 64 KiB are not read and answer 413; `mem_limit` 64 MB and `cpus` bound the damage (the container restarts); the network is internal and the edge is rate limited (P6.2) | Medium |
| Elevation of Privilege | A memory-safety bug in the service or in fcl-web is exploited | Pascal strings and arrays carry their length; range and overflow checks are compiled in (`-Cr -Co`); warnings, notes and hints are errors; distroless runtime image without a shell or package manager; non-root user (UID 10001); request bodies are never interpreted | Low |
| Tampering (supply chain) | The pasfmt source changes upstream | pasfmt is built from a fixed commit of its v0.7.0 tag with `--locked` dependencies, and only in the lint toolchain | Low |

The Medium residual risk (one thread per connection) is accepted for an
internal, read-only service on a segmented network; only High risks are
registered in `docs/governance/RISK_REGISTER.md`.
