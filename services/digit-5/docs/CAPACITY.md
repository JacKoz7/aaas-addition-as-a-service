# Capacity Plan — `digit-5`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-5` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-19 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-5` | 64m | 0.5 | Compiled language (Dart, AOT): default limit for compiled services (`CLAUDE.md` 6.2). Measured usage, including the flood scenario below, stays far below it. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10). No addition calls the digit services yet (P2.13), so
the load scenarios are synthetic: client containers on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-5` | 2.5 MiB | 6.2 MiB | < 1% (sampled after the run) | 2 000 `GET /next` on one keep-alive connection at 0.13 ms per call; 300 `GET /value` on new connections at 0.33 ms per call; 8 concurrent keep-alive clients: 4 000 calls in 0.40 s, no error | 2026-10-19 |
| `digit-5` | — | 7.3 MiB | — | 256 idle connections open at once (the connection limit) | 2026-10-19 |
| `digit-5` | — | 16.8 MiB | — | Two clients at once, each opening 256 connections and sending 1 MB request heads, repeated six times (answered 431 or refused at the limit); the service stayed healthy | 2026-10-19 |

Image size: 19.5 MB (`aaas/digit-5:dev`: `scratch` with the Dart runtime
files, the SQLite library, the AOT executable and busybox `wget`).
Database file: one row; it does not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers a few hundred bytes. It grows with the number of open
connections; the limit of 256 connections, the 8 KiB head limit, the
64 KiB body limit (bodies are skipped, not kept) and the 16 KiB read
while closing bound it. The Dart heap is not returned to the system at
once after a burst, which the flood figure includes. The largest
addition, 99 999 + 99 999, makes at most 99 999 successor steps; each step
calls one or more digit services once, a load the measured latency
handles in seconds.
