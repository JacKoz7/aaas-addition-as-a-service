# Service Level Objectives — `successor`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.1 |
| Last Reviewed | 2026-10-26 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose healthcheck, Prometheus (from P7.1) |

| Correctness | Calls answered with `n + 1` and logged and published exactly once: `computed + replayed` among calls that did not fail | Unit tests (the whole domain against the digit table and a carry oracle), contract and E2E tests; `successor_calls_total{outcome}` |
| Availability of calls | 1 − `failed` / all calls | `successor_calls_total{outcome}` |
| Latency | p99 of `successor_call_duration_seconds` | `successor_call_duration_seconds` |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |

| Correctness | 100% (a wrong successor is a wrong sum) | none |
| Availability of calls | 99.9% | 1 failed call per 1 000; the caller retries |
| Latency | p99 below 50 ms | 0.1% of calls slower |

Measured on 2026-10-26 with successor 0.2.0 (2000 sequential calls of one
task, each through a digit service, 200 of them also through `carry`):
p50 2.64 ms, p99 7.11 ms, maximum 50.5 ms; 0 failed calls. With the native
`+` of 0.1.0 (2026-10-17): p50 2.0 ms, p99 5.7 ms, maximum 42.3 ms.

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose. Objectives are
measured while the system is running (`make up`); time when the host is
switched off is excluded from the window.
