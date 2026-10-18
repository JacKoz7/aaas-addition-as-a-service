# Service Level Objectives — `digit-0`

| Field | Value |
| --- | --- |
| Document | Service Level Objectives |
| Component | `digit-0` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |
| Measurement Window | Rolling 30 days |

## 1. Service Level Indicators

| SLI | Definition | Measured From |
| --- | --- | --- |
| Availability | Successful `GET /health` probes / all probes | Compose healthcheck, Prometheus (from P7.1) |
| Correctness | `GET /value` and `GET /next` answers equal to the seeded row / all such answers | Contract test (`make contract-digit-0`), unit tests; answers are read from the database on every request |
| Success ratio | `digit_requests_total{outcome="ok"}` / `digit_requests_total` | `/metrics` |
| Latency | Duration of `GET /next` seen by the caller | Measured with a keep-alive client (CAPACITY.md); a server-side histogram arrives with P7.2 |

## 2. Objectives

| SLI | Objective | Error Budget (30 days) |
| --- | --- | --- |
| Availability | 99.9% | 43 minutes 12 seconds |
| Correctness | 100% (any wrong answer is an incident) | None |
| Success ratio | 99.99% | 1 failed request in 10 000 |
| Latency | 99% of `GET /next` below 5 ms on the host | 1% of requests |

## 3. Error Budget Policy

- Budget remaining: feature work and refactoring proceed normally.
- Budget exhausted: only reliability fixes are merged until the budget
  recovers; the owning team writes a postmortem
  (`docs/governance/INCIDENT_POSTMORTEM_TEMPLATE.md`).

## 4. Caveats

AaaS runs on a single workstation with Docker Compose. Objectives are
measured while the system is running (`make up`); time when the host is
switched off is excluded from the window.
