# Capacity Plan — `digit-6`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-6` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-19 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-6` | 64m | 0.5 | Compiled language (Swift): default limit for compiled services (`CLAUDE.md` 6.2). Measured usage, including the flood scenario below, stays far below it. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10). No addition calls the digit services yet (P2.13), so
the load scenarios are synthetic: client containers on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-6` | 1.1 MiB | 1.6 MiB | < 1% (sampled after the run) | 2 000 `GET /next` on one keep-alive connection at 0.08 ms per call; 300 `GET /value` on new connections at 0.19 ms per call; 8 concurrent keep-alive clients: 4 000 calls in 0.23–0.64 s over two runs, no error | 2026-10-19 |
| `digit-6` | — | 10.1 MiB | — | 256 idle connections open at once (the connection limit, one thread each) | 2026-10-19 |
| `digit-6` | — | 10.1 MiB | — | Two clients at once, each opening 256 connections and sending 1 MB request heads, three rounds (answered 431, cut off after 16 KiB, or refused at the limit); the service stayed healthy | 2026-10-19 |

Image size: 70.4 MB (`aaas/digit-6:dev`: distroless cc-debian13, 54 MB of
it, with the SQLite library, the executable with the Swift runtime linked
statically, and busybox `wget`). Database file: one row; it does not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers a few hundred bytes. It grows with the number of open
connections, by about 35 KiB each (a thread with a 256 KiB stack, of which
little is touched, and its buffers); the limit of 256 connections, the
8 KiB head limit, the 64 KiB body limit (bodies are skipped in 16 KiB
chunks, not kept) and the 16 KiB read while closing bound it. The largest
addition, 99 999 + 99 999, makes at most 99 999 successor steps; each step
calls one or more digit services once, a load the measured latency handles
in seconds.
