# Service Charter — `carry`

| Field | Value |
| --- | --- |
| Document | Service Charter |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Service Version | 0.1.0 |
| Last Reviewed | 2026-10-26 |
| Review Cadence | On every minor version of the service, and at least once per phase |

## 1. Mission

`carry` propagates a carry of one to the higher decimal positions of a
number: given the digits of a number and the position that receives the
carry, it asks the digit services for the successor of each visited digit
and continues while they report a carry (`CLAUDE.md` 3, step 7). It serves
the gRPC method `CarryService.Propagate` (`CLAUDE.md` 4.3), records every
call in Mnesia and announces it as `aaas.carry.propagated.v1`. It does
nothing else.

## 2. Business Value

AaaS computes `a + b` as `b` successor steps (`CLAUDE.md` 1, rule 5), and a
successor step of a number ending in 9 is not finished until the carry has
reached a digit that does not wrap. `carry` guarantees the **correctness**
of those steps: `9 + 1 = 10`, `99 + 1 = 100` and `99 999 + 1 = 100 000`
come out right because the carry visits every 9 above the units digit and
creates the new highest digit when needed, always through the digit
services. Its propagation log makes a retried step safe: one step, one
answer, one audit event. Without it, about one successor step in ten could
not complete and no addition crossing a multiple of ten would finish.

## 3. Stakeholders

| Stakeholder | Interest |
| --- | --- |
| Arithmetic Excellence Center (AEC) | Owns, builds and operates the service; owns `successor`, its caller (from P2.13b), and the ten digit services it calls |
| Transaction Integrity Office (TIO) | The saga (P3.3) drives the successor steps whose carries this service completes |
| Observability Steering Group (OSG) | Dashboards and alerts from the metrics (P7.3, P7.4) |
| End user of the calculator | Receives a correct result of the addition |

## 4. Scope

### In Scope

- `CarryService.Propagate` on gRPC port 9090.
- The calls to `GET /next` of the ten digit services.
- The propagation log in Mnesia, its migrations and its retention.
- The event `aaas.carry.propagated.v1`.
- `GET /health` and `GET /metrics` on port 8080.

### Out of Scope

- Any user-visible feature beyond the calculator keypad, display, timer and
  invoice download (`CLAUDE.md` section 1).
- Access to the database of any other service (`CLAUDE.md` section 1,
  rule 4).
- The units digit of a successor step (asked by `successor`) and any
  digit arithmetic of its own: every successor of a digit comes from that
  digit's service.
- Consuming events.

## 5. Key Performance Indicators

| KPI | Definition | Target | Source |
| --- | --- | --- | --- |
| Availability | Share of successful `GET /health` probes | See SLO.md | Compose healthcheck; Prometheus from P7.1 |
| Successful calls | (`ok` + `replayed`) / all `carry_propagations_total` excluding `invalid_argument` | See SLO.md | `/metrics` |
| Latency | p99 of `carry_propagation_duration_seconds` | See SLO.md | `/metrics` |
| Throughput | Rate of `carry_propagations_total` | Informational | `/metrics` |

## 6. Related Documents

[RACI](RACI.md) · [SLO](SLO.md) · [Runbook](RUNBOOK.md) ·
[Threat Model](THREAT_MODEL.md) · [Data Classification](DATA_CLASSIFICATION.md) ·
[Dependencies](DEPENDENCIES.md) · [Capacity](CAPACITY.md) · [API](API.md) ·
[Changelog](CHANGELOG.md) · [README](../README.md)
