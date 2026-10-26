# Service Level Objectives — `carry`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-26 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose healthcheck, Prometheus (from P7.1) |
| Correctness | Calls answered with the digits plus a carry at the position, recorded and published once per `(task_id, digits, position)` | Unit tests; `carry_propagations_total{outcome}` |
| Availability of calls | 1 − (`unavailable` + `internal`) / (all − `invalid_argument`) | `carry_propagations_total{outcome}` |
| Latency | p99 of `carry_propagation_duration_seconds` | `/metrics` |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |
| Correctness | 100% (a wrong carry is a wrong sum) | none |
| Availability of calls | 99.9% | 1 failed call per 1 000; the caller retries |
| Latency | p99 below 50 ms | 0.1% of calls slower |

Measured on 2026-10-26 with one sequential gRPC caller on the `services`
network (round trip at the caller, 0.5 CPU, one scheduler): carry at
position 1 of `[0, 3]` (one digit service call) p50 0.81 ms, p99 20.8 ms;
of `[0, 9, 9, 9, 9]` (five calls) p50 1.04 ms, p99 18.1 ms over 5 000
calls; 0 failed calls. With 8 concurrent callers the p99 was 58 ms, above
the objective, because the container is throttled at 0.5 CPU; the
successor calls the service sequentially (CAPACITY.md).

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose. Objectives are
measured while the system is running (`make up`); time when the host is
switched off is excluded from the window. A failure of a digit service or
of the broker counts against this service's availability of calls,
because the call cannot complete without them.
