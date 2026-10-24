# Capacity Plan — `digit-8`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-8` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-24 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-8` | 64m | 0.5 | Compiled language (D): default limit for compiled services (`CLAUDE.md` 6.2). Measured usage, including the flood scenario below, stays below half of it. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10), and with the cgroup's `memory.peak` for the peak of
the flood. No addition calls the digit services yet (P2.13), so the load
scenarios are synthetic: client containers on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-8` | 3.2 MiB | — | < 1% (sampled after the run) | 2 000 `GET /next` on one keep-alive connection at 0.037 ms per call; 300 `GET /value` on new connections at 0.17 ms per call; 8 concurrent keep-alive clients: 4 000 calls in 0.17–0.27 s over two runs, no error | 2026-10-24 |
| `digit-8` | — | 25 MiB | — | 256 idle connections open at once (the connection limit, one thread each); 16 MiB after they closed | 2026-10-24 |
| `digit-8` | 9–16 MiB after each round | 27 MiB | — | Two clients at once, each opening 256 connections and sending 1 MB request heads, ten rounds (answered 431, cut off after 16 KiB, or refused at the limit); the service stayed healthy | 2026-10-24 |

After a burst the process keeps the garbage-collected heap it grew to
(about 16 MiB); the D garbage collector reuses it for the next burst
instead of growing further, so the usage stays level from round to round.

The first build of the service did not join ended connection threads. A
druntime thread keeps its stack mapped until it is joined or its `Thread`
object is finalised by the garbage collector, so each connection left
about 10 KiB of resident stack behind: the same flood grew by 9 MiB per
round and the container was stopped by the memory limit in round ten. Each
connection thread now joins the one that ended before it (ADR-0030), and a
unit test checks that 100 connections leave no stacks behind.

Image size: 6.49 MB (`aaas/digit-8:dev`: `scratch` with the stripped
static executable, 2.9 MB, which holds druntime, Phobos, musl and
SQLite, plus busybox `wget` and the migrations). Database file: one row;
it does not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers a few hundred bytes. It grows with the number of open
connections, by about 85 KiB each (a thread with a 256 KiB stack, of which
little is touched, its 16 KiB receive buffer and the garbage its requests
leave until the next collection); the limit of 256 connections, the 8 KiB
head limit, the 64 KiB body limit (bodies are skipped in 16 KiB chunks,
not kept) and the 16 KiB read while closing bound it. The largest
addition, 99 999 + 99 999, makes at most 99 999 successor steps; each step
calls one or more digit services once, a load the measured latency handles
in seconds.
