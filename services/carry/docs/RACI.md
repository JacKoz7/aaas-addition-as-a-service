# RACI Matrix — `carry`

| Field | Value |
| --- | --- |
| Document | RACI Matrix |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-26 |

## 1. Roles

**R** Responsible (does the work) · **A** Accountable (one per activity,
signs off) · **C** Consulted (two-way, before the decision) · **I** Informed
(one-way, after the decision).

In practice every team is represented by the repository owner
(`@JacKoz7` in `CODEOWNERS`); the matrix records which organisational role
each decision belongs to.

## 2. Matrix

| Activity | AEC | TIO | PEG | TIB | OSG |
| --- | --- | --- | --- | --- | --- |
| Code change within the service | R, A | I | I | I | I |
| Contract change (`carry.proto`, `aaas.carry.propagated.v1`) | R, A | C | C | I | C |
| Deployment (`make up`, release tag) | R, A | I | C | I | I |
| Incident response | R, A | C | C | I | C |
| Database migration (Mnesia tables) | R, A | C | I | I | I |
| Retention change (`AAAS_RETENTION_HOURS`) | R, A | C | I | I | C |
| Security finding | R | I | I | A | I |
| Alert and dashboard change | R | I | I | I | A |
| Capacity (memory limit) change | R, A | I | C | I | C |

The Transaction Integrity Office is consulted on contract changes because
its saga drives the successor steps that call this service (from P3.3).

## 3. Escalation Path

1. Arithmetic Excellence Center (AEC), service owner.
2. Platform Enablement Guild (PEG) for platform and infrastructure issues
   (Redpanda, Compose).
3. Repository owner (`@JacKoz7`).
