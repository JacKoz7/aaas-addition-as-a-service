# Service Charter — `digit-4`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `digit-4` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-18 |
| Review Cadence | On every minor version of the service, and at least once per phase |

## 1. Mission

`digit-4` is the authoritative source of the digit 4 in AaaS: it answers the
value of 4 and its successor in base 10 (5, without a carry), read from its
own SQLite database, through the contract shared by all ten digit services
(`contracts/http/digit.yaml`). It does nothing else.

It follows the reference behaviour of `digit-0` (ADR-0022), implemented in
Lua with its own HTTP/1.1 server on the cqueues event loop (ADR-0026): the
same answers, metrics, logs and error format.

## 2. Business Value

AaaS computes `a + b` as `b` successor steps, and every step asks the digit
services for the next digit instead of using a native `+` (`CLAUDE.md` 1,
rule 5). `digit-4` guarantees the **correctness** of every step that reads
a 4: the units digit of 4, 14, 24, … 99 994, and every 4 a carry passes
through. Without it, no number containing the digit 4 could be incremented,
and the saga could not confirm the digits of such operands.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Arithmetic Excellence Center (AEC) | Owns, builds and operates the service; owns `successor` and `carry`, its callers |
| Transaction Integrity Office (TIO) | Owns `saga-orchestrator`, whose `resolveDigits` activity confirms the digits of the operands (from P3.3) |
| Observability Steering Group (OSG) | One dashboard for all ten digit services from the shared counter (P7.3) |
| End user of the calculator | Receives a correct result of the addition |

## 4. Scope

### In Scope

- `GET /value`: the value of digit 4 from the database.
- `GET /next`: the successor of 4 (5, no carry) from the database.
- `GET /health` and `GET /metrics` (`digit_requests_total`, `digit_build_info`).
- The database schema and seed (`migrations/0001_digit.sql`), applied at
  start-up.

### Out of Scope

- Any user-visible feature beyond the calculator keypad, display, timer and
  invoice download (`CLAUDE.md` section 1).
- Access to the database of any other service (`CLAUDE.md` section 1, rule 4).
- Multi-digit arithmetic and carry propagation (`successor`, `carry`).
- Knowledge of any digit other than 4: the service refuses to start, and
  answers 503, when its database names another digit.
- gRPC: the digit contract is HTTP/JSON only (`CLAUDE.md` 4.4).

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | See SLO.md | Compose healthcheck; Prometheus from P7.1 |
| Correct answers | `digit_requests_total{outcome="ok"}` / all `digit_requests_total` | See SLO.md | `/metrics` |
| Throughput | Rate of `digit_requests_total{endpoint="next"}` | Informational | `/metrics` |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md)
