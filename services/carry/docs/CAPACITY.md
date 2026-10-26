# Capacity — `carry`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-26 |

## 1. Limits

| Resource | Limit | Reason |
| --- | --- | --- |
| Memory | `mem_limit: 128m` | Default for interpreted and VM languages (`CLAUDE.md` 6.2); Elixir runs on the BEAM |
| CPU | `cpus: 0.5` | Default of the AaaS services |
| Connections | 256 per listener (HTTP 8080, gRPC 9090) | Bounds the memory under a connection flood |
| Request body | 4 KiB (gRPC); never read (HTTP) | A `PropagateRequest` is below 60 bytes |
| Call budget | 1.8 s, at most 7 digit service calls | As the 1.8 s budget of `successor` (ADR-0016) |

## 2. Measurements (2026-10-26, Apple silicon host, Docker Desktop)

| Scenario | Memory | CPU |
| --- | --- | --- |
| Idle after start | 34.8 MiB | 0.0–0.5% |
| Peak (`memory.peak`) over 5 000 sequential calls, fresh container | 49.5 MiB | 0.5 CPU while busy |
| After 7 500 calls of 1 and 8 concurrent callers | 42.2 MiB (peak 63.9 MiB) | — |

The runtime image is 56 MB (Alpine 3.24, the release with its ERTS, the
BEAM libraries).

Latency at the caller (gRPC round trip, one connection, Nagle off at the
client):

| Load | p50 | p90 | p99 | Max |
| --- | --- | --- | --- | --- |
| 1 caller, 1 digit call per carry (1 000 calls) | 0.81 ms | 0.88 ms | 20.8 ms | 68.7 ms |
| 1 caller, 5 digit calls per carry (5 000 calls) | 1.04 ms | 1.24 ms | 18.1 ms | 68.1 ms |
| 8 callers, 1 digit call (4 000 calls) | 3.13 ms | 10.5 ms | 58.5 ms | 68.1 ms |

The tail above 15 ms is the CPU quota: at 0.5 CPU the kernel pauses the
container for the rest of a 100 ms period once it has used 50 ms.

Memory decisions (measured, see the Dockerfile):

- `RELEASE_MODE=interactive` loads modules when first used. The default
  (embedded) mode loads every module of every dependency at boot, 35 MB of
  code instead of 12 MB: 98 MiB at rest instead of 37 MiB, and a peak of
  126 MiB under load, too close to the limit.
- One scheduler (`+S 1:1`) instead of one per host core: with 8 concurrent
  callers p90 10 ms and a peak of 50 MiB, against 9 ms and 61 MiB with
  eight schedulers and 66 ms and 55 MiB with two.

## 3. Storage and Retention

| Data | Size | Growth | Bound |
| --- | --- | --- | --- |
| `carry_propagations` (dets file) | 0.96 KB per record (4.8 MB for 5 000 records) | One record per carry, about one per ten successor steps: about 10 000 records (9.6 MB) for the largest addition, 99 999 + 99 999 | Records older than `AAAS_RETENTION_HOURS` (24 h) are deleted hourly; dets limits the file to 2 GB (about 2 million records) |
| Mnesia schema and logs | Below 20 KB | None | — |
| `aaas.carry.propagated.v1` | About 400 bytes per event | One per record | Topic retention of Redpanda (ADR-0011) |

The memory does not grow with the log: the table is `disc_only_copies`
(no copy in RAM). dets does not shrink its file when records are deleted;
the space of deleted records is reused by new ones.

## 4. Scaling

One instance. Mnesia is local to the node, so a second instance would have
its own log, and a retried call reaching the other instance would be
computed again with a new `eventId` (still correct; consumers deduplicate
by `eventId`). Scaling out is not planned.
