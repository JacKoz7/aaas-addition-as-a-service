# Capacity Plan — `digit-7`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `digit-7` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-23 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `digit-7` | 128m | 0.5 | VM language (Gleam on the BEAM): default limit for interpreted and VM services (`CLAUDE.md` 6.2). Idle usage is about a fifth of it; the worst flood measured below peaked at 91 MiB, which leaves 37 MiB of margin. |

The emulator flags of the image (`services/digit-7/Dockerfile`) keep the
footprint small: `+P 4096` and `+Q 1024` size the process and port tables
for 256 connections instead of about one million processes and 65 536
ports (17 MB less at start-up), and the socket option `{buffer, 16384}`
caps what one receive returns. With `cpus: 0.5` the runtime puts one of
its schedulers online.

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up` (CLAUDE.md
section 8, rule 10). No addition calls the digit services yet (P2.13), so
the load scenarios are synthetic: client containers on `aaas-services`.

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `digit-7` | 23.5 MiB | 24 MiB | < 1% (sampled after the run) | 2 000 `GET /next` on one keep-alive connection at 0.18 ms per call; 300 `GET /value` on new connections at 0.25 ms per call; 8 concurrent keep-alive clients: 4 000 calls in 0.53–0.61 s over two runs, no error | 2026-10-23 |
| `digit-7` | — | 57 MiB | — | 256 idle connections open at once (the connection limit, one Erlang process each), after the load above | 2026-10-23 |
| `digit-7` | — | 91 MiB | — | Two clients at once, each opening 256 connections and sending 1 MB request heads (answered 431, or refused at the limit), ten rounds in a row: after each round 55, 61, 75, 83, 91, 73, 69, 61, 68 and 54 MiB; the service stayed healthy, no OOM kill | 2026-10-23 |

The memory the Erlang runtime uses (`erlang:memory()`) stays at about
15 MB through the floods, with 48 processes once they are over: nothing
is retained. The resident size above it is memory the runtime's
allocators keep for reuse after a burst of 512 connection processes. It
goes up and down from round to round instead of growing, and it does not
approach the limit.

Image size: 59.3 MB (`aaas/digit-7:dev`: Alpine 3.24 with the three
shared libraries of the emulator, the erts, kernel and stdlib parts of
Erlang/OTP 28, the compiled packages and the esqlite NIF). Database
file: one row; it does not grow.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). Memory does not grow with the operand size: each request reads
one row and answers a few hundred bytes. It grows with the number of open
connections (one Erlang process each, with its heap and receive buffer).
That growth is bounded by the limit of 256 connections, the 8 KiB head
limit, the 64 KiB body limit (bodies are skipped, not kept), the 16 KiB
receive buffer and the 16 KiB read while closing. The largest addition,
99 999 + 99 999, makes at most 99 999 successor steps; each step calls one
or more digit services once, a load the measured latency handles in
seconds.
