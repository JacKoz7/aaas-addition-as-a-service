# Capacity Plan — `successor`

| Field | Value |
| --- | --- |
| Document | Capacity Plan |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.1 |
| Last Reviewed | 2026-10-26 |

## 1. Limits

| Container | `mem_limit` | `cpus` | Justification |
| --- | --- | --- | --- |
| `successor` | 64m | 0.5 | Compiled language (GHC native code): default limit for compiled services (CLAUDE.md 6.2); the GHC heap is capped at 40 MB (`-M40m`), leaving room for librdkafka and the RTS. Unchanged by the gRPC server and client of 0.2.0 (measured below). |
| `successor-db` | 256m | 0.5 | Database default (CLAUDE.md 6.2). |

## 2. Measured Usage

Measured with `docker stats --no-stream` after `make up`, idle and during an
addition (CLAUDE.md section 8, rule 10).

| Container | Idle RAM | Peak RAM | Peak CPU | Scenario | Measured On |
| --- | --- | --- | --- | --- | --- |
| `successor` 0.2.0 | 11.3 MiB | 26.2 MiB (`memory.peak` of the container since its start) | 17.8% of one core | 2000 sequential `POST /v1/next` calls of one task (`n` = 1000 … 2999, the steps of 1000 + 2000; 200 of them carry) over one keep-alive connection in 6.07 s, each through a digit service and, for the 200, `carry`: mean 3.03 ms, p50 2.64 ms, p95 4.46 ms, p99 7.11 ms, max 50.5 ms; 0 failed | 2026-10-26, Apple silicon (arm64), Docker 27.5.1 |
| `successor` 0.1.0 (native `+`) | 16.3 MiB | 43.1 MiB | 12.8% of one core | the same 2000 calls in 4.7 s: p50 2.0 ms, p95 3.6 ms, p99 5.7 ms, max 42.3 ms | 2026-10-17, Apple silicon (arm64), Docker 27.5.1 |
| `successor-db` | 95.9 MiB | 139.9 MiB | 15.9% of one core | same scenario | 2026-10-17, Apple silicon (arm64), Docker 27.5.1 |

The 0.1.0 idle value is from a fresh `make clean && make up`, the 0.2.0
value from `make up` after the step's tests. Under load the GHC runtime
grows its allocation areas and librdkafka its buffers; the peak stays flat
however many calls follow. The gRPC server and the carry connection of
0.2.0 did not raise it.

## 3. Scaling Notes

AaaS runs one replica of every container on a single host (16 GB RAM
minimum). The waiting time of an addition grows linearly with the smaller
operand (CLAUDE.md section 1); capacity is planned for the largest addition,
99 999 + 99 999.

Memory of the service is constant per call. Time grows linearly with the
smaller operand: at the measured 3.03 ms per call (including the caller's
round trip, a digit call for every step and a carry call for every tenth),
99 999 calls take about 5 minutes in the successor alone. The call log grows by one
document per call: 2000 calls took 6.4 MB on disk before compaction (about
3.2 KB per call; 0.5 KB of JSON each), so 99 999 + 99 999 adds about
320 MB until CouchDB compacts the database (R-014).
