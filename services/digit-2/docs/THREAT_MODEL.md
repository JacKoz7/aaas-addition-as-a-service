# Threat Model — `digit-2`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-2` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-2-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 2); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 2 + 1 becomes something else | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | A client opens connections and sends nothing; the server answers one connection at a time | The request head must arrive within 500 ms and fit 8 KiB, the drain after the reply lasts at most 200 ms, so a silent connection delays other callers by at most about 0.7 s, below the 2 s call timeout; requests take about 0.15 ms; the network is internal and the edge is rate limited (P6.2) | Medium |
| Elevation of Privilege | A memory-safety bug in the HTTP parsing or in a C call is exploited | Fortran strings and arrays carry their length; the binary is built with `-fcheck=bounds` (the tests with `-fcheck=all`); C interfaces are explicit `bind(C)` declarations checked by the compiler; no trampolines (no executable stack); non-root user (UID 10001), minimal Alpine image; request bodies are never interpreted | Medium |

The Medium residual risks (a hand-written HTTP server answering one
connection at a time) are accepted for an internal, read-only service on a
segmented network; only High risks are registered in
`docs/governance/RISK_REGISTER.md`.
