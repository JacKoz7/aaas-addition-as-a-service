# Threat Model — `digit-1`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-1` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-1-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 1); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 1 + 1 becomes something else | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | A flood of requests or large bodies exhausts the four worker threads or memory | `mem_limit` and `cpus`; requests take about 0.09 ms; bodies above 1 KiB are refused with 413; idle keep-alive connections close after 10 s; the edge is rate limited (P6.2) | Low |
| Elevation of Privilege | A memory-safety bug in the service or in cpp-httplib is exploited | Non-root user (UID 10001), minimal Alpine image; the code uses standard containers and RAII, no raw buffers; g++ warnings as errors and clang-tidy (bugprone, cert, cppcoreguidelines, analyzer); cpp-httplib is a pinned release verified by SHA-256 (ADR-0023); request bodies are capped at 1 KiB and never interpreted | Medium |
| Tampering (supply chain) | The cpp-httplib header is replaced at download | The build fails unless the file matches the recorded SHA-256 (`ADD --checksum`) | Low |

The Medium residual risk of native code parsing HTTP is accepted for an
internal, read-only service on a segmented network; only High risks are
registered in `docs/governance/RISK_REGISTER.md`.
