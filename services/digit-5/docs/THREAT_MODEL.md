# Threat Model — `digit-5`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `digit-5` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-19 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2, ADR-0021).
- Data store: SQLite (embedded) in the volume `digit-5-data`, reachable only
  by this process.
- Trust boundaries: inbound HTTP from containers on `services` (callers:
  `successor`, `carry` from P2.13; `saga-orchestrator` from P3.3). The
  service calls nothing and consumes no events.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on the `services` network calls the service as if it were a legitimate caller | The service exposes only read operations on public data (digit 5); segmentation keeps the network internal | Low |
| Tampering | The digit row is altered, so that 5 + 1 becomes something else | The row is checked against `AAAS_DIGIT` on every request; the volume is private; consensus replicas verify every result independently (P4.5) | Low |
| Tampering (request smuggling) | A request whose body length is ambiguous is read differently by the service and a proxy in front of it | A request with both `Content-Length` and `Transfer-Encoding`, another transfer coding or an invalid length answers 400 and closes the connection (RFC 9112, 6.1 and 6.3); there is no proxy in front of the service | Low |
| Repudiation | A wrong answer cannot be traced | Every request can be logged at debug level with the caller's `traceId`; the counter records outcomes | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials | Low |
| Denial of Service | Many, silent or slow connections, or large heads and bodies, exhaust memory | Each connection is an asynchronous task, so a slow client delays only itself; at most 256 connections at once; a connection silent for 10 s is closed; heads above 8 KiB answer 431 and bodies above 64 KiB answer 413 without being read; at most 16 KiB is read while a connection closes. The `HttpServer` of `dart:io`, which accepts 1 MiB heads, is not used: with it, fewer than 16 such heads killed the container at its 64 MB limit (ADR-0027). The same flood against this server peaked at 16.8 MiB. `mem_limit` and `cpus` bound the damage; an OOM kill stops the container, which has no restart policy, until `make up` | Low |
| Elevation of Privilege | A bug in the HTTP parser is exploited | The parser is Dart code (memory-safe, bounds-checked); every line is matched by an anchored pattern and request bodies are discarded, never interpreted; SQLite is the Debian library loaded through FFI; scratch runtime image without a shell or package manager; non-root user (UID 10001) | Low |
| Tampering (supply chain) | A Dart package changes upstream | Every package version is exact in `pubspec.yaml` and locked with its checksum in `pubspec.lock` (`dart pub get --enforce-lockfile`); sqlite3 loads the system library instead of downloading a prebuilt one during the build | Low |

No risk is above Low; only High risks are registered in
`docs/governance/RISK_REGISTER.md`.
