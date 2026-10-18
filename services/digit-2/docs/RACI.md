# RACI Matrix — `digit-2`

| Field | Value |
| --- | --- |
| Document | RACI Matrix |
| Component | `digit-2` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |

**R** Responsible (does the work) · **A** Accountable (one per activity,
signs off) · **C** Consulted (two-way, before the decision) · **I** Informed
(one-way, after the decision).

In practice every team is represented by the repository owner
(`@JacKoz7` in `CODEOWNERS`); the matrix records which organisational role
each decision belongs to.

| Activity | AEC | TIO | PEG | TIB | OSG |
| --- | --- | --- | --- | --- | --- |
| Code change within the service | R, A | I | I | I | I |
| Contract change (`contracts/http/digit.yaml`, all ten digit services) | R, A | C | C | I | C |
| Deployment (`make up`, release tag) | R, A | I | C | I | I |
| Incident response | R, A | C | C | I | C |
| Database migration (seed of the digit) | R, A | C | I | I | I |
| Security finding | R | I | I | A | I |
| Alert and dashboard change | R | I | I | I | A |
| Capacity (memory limit) change | R, A | I | C | I | C |

The callers of the service, `successor` and `carry` (AEC) and
`saga-orchestrator` (TIO), are consulted on every contract change, because
the contract is shared by all ten digit services (ADR-0021).

## Escalation Path

1. Arithmetic Excellence Center (AEC), service owner.
2. Platform Enablement Guild (PEG) for platform and infrastructure issues.
3. Repository owner (`@JacKoz7`).
