# Capacity Plan — `digit-2`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-2` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-2` | 64m | 0.5 | Compiled language: default limit for compiled services (`CLAUDE.md` 6.2). Measured usage is far below; the default is kept so that all compiled services share one class. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10). No addition calls the digit services yet (P2.13), so
the load scenario is synthetic: a client container on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-2` | 0.8 MiB | 0.8 MiB | < 1% (sampled after the run) | One request per connection (`Connection: close`): 2 000 sequential `GET /next` at 0.18 ms per call, 300 `GET /value` at 0.15 ms per call; 8 concurrent clients: 4 000 calls in 0.44 s, no error | 2026-10-18 |

Image size: 18.3 MB (`aaas/digit-2:dev`). Database file: one row; it does
not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers a few hundred bytes; the request head is capped at
8 KiB. The server answers one connection at a time, which the measured
throughput (about 9 000 calls per second) covers for every caller. The largest addition, 99 999 + 99 999,
makes at most 99 999 successor steps; each step calls one or more digit
services once, a load the measured latency handles in seconds.
