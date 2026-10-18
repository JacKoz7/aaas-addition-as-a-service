# Capacity Plan — `digit-0`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-0` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-0` | 64m | 0.5 | Compiled language: default limit for compiled services (`CLAUDE.md` 6.2). Measured usage is far below; the default is kept so that all compiled services share one class. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10). No addition calls the digit services yet (P2.13), so
the load scenario is synthetic: a client container on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-0` | 1.2 MiB | 1.2 MiB | < 1% (sampled after the run) | 2 000 `GET /next` on one keep-alive connection: 0.065 ms per call; 300 calls with a new connection each: 0.222 ms per call | 2026-10-18 |

Image size: 26.5 MB (`aaas/digit-0:dev`). Database file: one row; it does
not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers at most 4 KiB. The largest addition, 99 999 + 99 999,
makes at most 99 999 successor steps; each step calls one or more digit
services once, a load the measured latency handles in seconds.
