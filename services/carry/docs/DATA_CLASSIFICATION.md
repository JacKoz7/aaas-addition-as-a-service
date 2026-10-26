# Data Classification — `carry`

| Field | Value |
| --- | --- |
| Document | Data Classification |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-26 |

## 1. Classification Levels

| Level | Meaning |
| --- | --- |
| PUBLIC | May be shown to anyone (for example the result of 2 + 3) |
| INTERNAL | Operational data of AaaS; not shown to users |
| CONFIDENTIAL | Credentials, tokens and identifiers linkable to a person |

## 2. Data Inventory

Store: Mnesia (embedded), volume `carry-data`. The service has no
credentials: Mnesia runs inside its process and Redpanda needs none until
P5.3.

| Data Item | Location | Classification | Retention | Personal Data |
| --- | --- | --- | --- | --- |
| Propagation records (`task_id`, `digits`, `position`, `result`, `event_id`, `event`, `propagated_at`, `trace_id`) | Mnesia `carry_propagations` | INTERNAL | `AAAS_RETENTION_HOURS` (default 24 h), deleted hourly | No |
| Migration records | Mnesia `carry_migrations` | INTERNAL | Lifetime of the volume | No |
| Mnesia schema and logs (`schema.DAT`, `LATEST.LOG`) | Volume `carry-data` | INTERNAL | Lifetime of the volume | No |
| Published events (digits, position, result, identifiers, traceparent) | Redpanda `aaas.carry.propagated.v1` | INTERNAL | Topic retention (ADR-0011) | No |
| Log fields `taskId`, `traceId`, `spanId`, digits, positions, failure details | stdout (container logs, Loki from P7.1) | INTERNAL | Docker log rotation; Loki retention from P7.1 | No |

## 3. Personal Data

None. A task identifier identifies an addition, not a person; the link
between a task and the guest session that started it is held by
`expression-assembler`, not by this service (`docs/governance/DPIA.md`).

## 4. Deletion

`docker volume rm aaas_carry-data` (or `make clean`) deletes every record;
the retention job deletes records older than `AAAS_RETENTION_HOURS`.
