# Capacity Plan — `digit-4`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-4` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-4` | 128m | 0.5 | Interpreted language (Lua): default limit for interpreted services (`CLAUDE.md` 6.2). Measured usage is far below; the default is kept so that all interpreted services share one class. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10). No addition calls the digit services yet (P2.13), so
the load scenario is synthetic: a client container on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-4` | 1.8 MiB | 3.1 MiB | < 1% (sampled after the run) | 2 000 `GET /next` on one keep-alive connection at 0.09 ms per call; 300 `GET /value` on new connections at 0.19 ms per call; 8 concurrent keep-alive clients: 4 000 calls in 0.25 s, no error (2.0 MiB); 256 idle connections open at once, the connection limit (3.1 MiB) | 2026-10-18 |

Image size: 20.9 MB (`aaas/digit-4:dev`, Alpine with the Lua interpreter,
cqueues, lsqlite3, luaposix and their libraries). Database file: one row;
it does not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers a few hundred bytes. Memory grows with the number of
open connections, by about 5 KiB each (a coroutine and its buffers); the
limit of 256 connections bounds it at a few MiB. Request heads are capped at
8 KiB and request bodies are discarded in 4 KiB chunks up to 64 KiB, so no
request holds more than a few KiB. The largest addition, 99 999 + 99 999,
makes at most 99 999 successor steps; each step calls one or more digit
services once, a load the measured latency handles in seconds.
