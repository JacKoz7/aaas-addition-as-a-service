# Data Classification — `digit-8`

| Field | Value |
| --- | --- |
| Document | Data Classification |
| Component | `digit-8` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-24 |

## 1. Classification Levels

| Level | Meaning |
| --- | --- |
| PUBLIC | May be shown to anyone (for example the result of 2 + 3) |
| INTERNAL | Operational data of AaaS; not shown to users |
| CONFIDENTIAL | Credentials, tokens and identifiers linkable to a person |

## 2. Data Inventory

Store: SQLite (embedded), volume `digit-8-data`, file `/data/digit-8.db`.

| Data Item | Location | Classification | Retention | Personal Data |
| --- | --- | --- | --- | --- |
| Table `digit` (digit 8, value 8, successor 9, no carry) | SQLite | PUBLIC | Lifetime of the volume | No |
| Table `schema_migrations` (applied file names and times) | SQLite | INTERNAL | Lifetime of the volume | No |
| Log lines (`ts`, `level`, `service`, `msg`, `traceId`, `spanId`, `detail`) | stdout (Loki from P7.1) | INTERNAL | Docker log rotation; Loki retention from P7.1 | No |
| Request counters | Process memory, `/metrics` | INTERNAL | Until the process stops | No |

The service has no database password: SQLite is embedded and the file is
protected by the volume.

## 3. Handling Rules

- Data is never read by another service directly (`CLAUDE.md` section 1,
  rule 4); other services obtain it through the contracts in API.md.
- No request body is interpreted (bodies up to 64 KiB are read and
  discarded, larger ones are not read) and no session or user identifier is
  processed, so the service holds no personal data
  (`docs/governance/DPIA.md`).
- Deleting the `digit-8-data` volume (`make clean`) erases all stored data;
  the next start recreates the seed.
