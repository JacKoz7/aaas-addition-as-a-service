# Capacity Plan — `digit-9`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-9` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-25 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-9` | 128m | 0.5 | Racket runs on the Chez Scheme virtual machine: default limit for interpreted and VM services (`CLAUDE.md` 6.2). The Racket runtime alone holds about 70 MiB; the measured peak, including the flood scenario below, is 86.1 MiB. |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10), and with the cgroup's `memory.peak` for the peaks. No
addition calls the digit services yet (P2.13), so the load scenarios are
synthetic: client containers on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-9` | 70.9 MiB | — | 0.1–0.3% idle (the memory guard wakes five times a second) | 2 000 `GET /next` on one keep-alive connection at 0.073–0.100 ms per call; 300 `GET /value` on new connections at 0.18 ms per call; 8 concurrent keep-alive clients: 4 000 calls in 0.15–0.23 s over two runs, no error | 2026-10-25 |
| `digit-9` | — | 76.7 MiB | — | 256 idle connections open at once (the connection limit, one Racket thread each) | 2026-10-25 |
| `digit-9` | 69–74 MiB after each round | 86.1 MiB | — | Two clients at once, each opening 256 connections and sending 1 MB request heads, ten rounds (answered 431, cut off after 16 KiB, or refused at the limit); the service stayed healthy | 2026-10-25 |

Almost all of the idle memory is the Racket runtime: the boot files of
Chez Scheme and Racket, the macro expander and the compiled libraries,
which `raco exe` and plain `racket` load alike (70–72 MiB of anonymous
memory in both). Racket's `db` library is not used: loading it doubled the
memory of the process (142 MiB, ADR-0031).

### The memory guard

Racket CS collects the young generations often but keeps the memory they
free mapped for reuse; only a major collection returns it to the system,
and a major collection starts only when the heap has doubled since the
previous one. With a runtime of about 60 MiB of heap, that is near
130 MiB, above the limit. The first build had no guard and allocated a
new input buffer for every receive: the flood above peaked at 125 MiB and
the process kept 111–119 MiB after it, while the live heap was about
71 MiB. One reused input buffer per connection lowered the peak to
114 MiB; the rest was freed memory that stayed mapped.

`src/digit9/memory.rkt` checks the memory the runtime holds from the
system (Chez Scheme's `current-memory-bytes`) every 200 ms and runs a major
collection when it is 12 MiB above its size after the previous collection.
A major collection takes 3–5 ms, because the runtime lives in the static
generation. With the guard, the same flood peaked at 86.1 MiB and the
process held 69–74 MiB after each round.

Image size: 84 MB (`aaas/digit-9:dev`: Alpine 3.24 with the libraries of
the Racket runtime and SQLite, the executable of `raco exe`, 3.0 MB, and
the Racket CS runtime it needs, 53.5 MB). Database file: one row; it does
not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers a few hundred bytes. It grows with the number of open
connections, by about 23 KiB each (a Racket thread, its 4 KiB input
buffer and the buffers of its TCP ports); the limit of 256 connections,
the 8 KiB head limit (the input buffer stays at most 16 KiB), the 64 KiB
body limit (bodies are skipped, not kept) and the 16 KiB read while closing
bound it, and the memory guard returns the garbage of a burst to the
system. The largest addition, 99 999 + 99 999, makes at most 99 999
successor steps; each step calls one or more digit services once, a load
the measured latency handles in seconds.
