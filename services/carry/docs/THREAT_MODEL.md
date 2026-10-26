# Threat Model — `carry`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-26 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Network: `services` only. No port is published on the host and the
  gateway has no route to the service (`CLAUDE.md` 6.2).
- Data store: Mnesia inside the service process, files in the volume
  `carry-data`, reachable only by this process.
- Trust boundaries: inbound gRPC (9090) and HTTP (8080) from containers on
  `services` (caller: `successor` from P2.13b; the Compose healthcheck);
  outbound HTTP to the ten digit services and Kafka to Redpanda.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on `services` calls `Propagate` as if it were the successor, or impersonates a digit service | Segmentation keeps the network internal; every answer of a digit service is checked against the contract (digit asked, successor in 0..9) and a wrong answer fails the call; consensus replicas verify every result independently (P4.5) | Low |
| Tampering | Forged calls fill the propagation log with wrong entries for a task | A record holds only what the digit services answered, so a forged call stores a correct carry; the key includes the digits, so it cannot replace the record of another call; the volume is private | Low |
| Tampering (supply chain) | A Hex package changes upstream | Every dependency is pinned in `mix.exs` and by checksum in `mix.lock`; the base images and Alpine packages are pinned; the runtime image holds only the release | Low |
| Repudiation | A carry cannot be traced | Every call is recorded with its `trace_id` and published as an event with its `traceparent`; failures are logged with the task and trace identifiers | Low |
| Information Disclosure | Data leaks | The service holds no confidential data (DATA_CLASSIFICATION.md) and no credentials; malformed task identifiers are not copied into log lines | Low |
| Denial of Service | Many connections, large or many requests exhaust memory or CPU | At most 256 connections per listener; gRPC request bodies above 4 KiB refused; HTTP bodies never read and connections closed after 10 s of silence; each call bounded to 1.8 s and 7 digit calls; `mem_limit` and `cpus` bound the damage | Low |
| Denial of Service (storage) | Many distinct calls fill the volume | About 0.96 KB per record; records older than 24 h are deleted hourly; the dets file of Mnesia is limited to 2 GB (about 2 million records), beyond which writes fail with `UNAVAILABLE` instead of corrupting data | Low |
| Elevation of Privilege | A bug in a parser is exploited | Protocol parsing is done by Cowboy (HTTP/1.1, HTTP/2) and protobuf on the memory-safe BEAM; the only native code is the crc32cer NIF of brod (checksums of Kafka batches written by the service itself); non-root user (UID 10001); minimal Alpine image without a shell other than busybox | Low |

Known advisory: EEF-CVE-2026-43966 (cowlib 2.21.0, HTTP response
splitting through `cow_http_struct_hd:escape_string/2`, no fixed version
yet). The service builds no structured-field header from external input,
so the vulnerable function is never reached with attacker data; the
advisory is reviewed when cowlib publishes a fix.

No risk is above Low; only High risks are registered in
`docs/governance/RISK_REGISTER.md`.
