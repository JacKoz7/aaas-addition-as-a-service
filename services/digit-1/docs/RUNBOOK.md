# Runbook — `digit-1`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `digit-1` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=digit-1` |
| Health | `docker compose exec digit-1 wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `docker compose exec digit-1 wget -qO- http://127.0.0.1:8080/metrics` |
| Contract test | `make contract-digit-1` |
| Restart | `docker compose restart digit-1` |
| Rebuild | `make build-digit-1 && make up` |

## 2. Alerts

Every alert defined for this service has one section below: meaning,
diagnosis step by step, remediation, escalation. Alerting is introduced in
step P7.4; until then this section lists the failure modes detected by the
Compose healthcheck and the logs.

### 2.1 Container unhealthy

- **Meaning**: the Compose healthcheck (`GET /health`, every 10 s, 2 s
  timeout) failed five times in a row after the 10 s start period. The
  health check fails when the digit row cannot be read or names another
  digit than `AAAS_DIGIT`.
- **Diagnosis**:
  1. `make ps` — confirm the state of `digit-1`.
  2. `make logs SVC=digit-1` — look for `"level":"error"` lines:
     `cannot read the digit from the database` (SQLite error in `detail`)
     or `the database holds another digit`.
  3. Inspect the database (section 3).
- **Remediation**: a missing or wrong row means the volume was altered;
  recreate it (section 3). Then `docker compose restart digit-1`.
- **Escalation**: Arithmetic Excellence Center (AEC), then PEG (RACI.md).

### 2.2 Service exits at start-up

- **Meaning**: the container restarts or stays `exited` with status 1.
- **Diagnosis**: the last log lines name the cause:
  `unsupported AAAS_BOOTSTRAP` (only `env` exists before P5.2),
  `AAAS_DIGIT must be 0..9`, `AAAS_HTTP_PORT must be 1..65535`,
  `the database cannot be prepared` (the reason in `detail`: the file
  cannot be opened, a migration failed, or the table holds no row),
  `the database does not hold the configured digit`, or
  `cannot start the HTTP server` (port taken).
- **Remediation**: correct the environment in `compose/services.yml`, or
  recreate the volume (section 3) when a migration or the seed failed.
- **Escalation**: AEC.

### 2.3 Error answers (`outcome="error"`)

- **Meaning**: `digit_requests_total{outcome="error"}` grows: `/value` or
  `/next` answered 503 because the row could not be read.
- **Diagnosis**: as 2.1; the error lines carry the SQLite message.
- **Remediation**: as 2.1. Callers retry 503 answers (the contract marks
  them retryable), so no addition is lost while the service recovers.
- **Escalation**: AEC.

## 3. Database (SQLite, embedded)

- **Inspect**: `docker run --rm -v aaas_digit-1-data:/data alpine:3.22.2 sh -c
  'apk add -q sqlite && sqlite3 /data/digit-1.db "SELECT * FROM digit; SELECT * FROM schema_migrations;"'`
  (the volume name is `<project>_digit-1-data`; see `docker volume ls`).
  Expected: `1|1|2|0` and one migration row.
- **Restore**: the database holds only the seed, so it is recreated rather
  than restored: `docker compose stop digit-1`, `docker volume rm
  aaas_digit-1-data`, `make up`; the migrations recreate the row at start-up.
- **In-flight additions**: a digit call is a single read; a caller whose
  call fails retries it (successor and carry from P2.13), so a restart of
  the service only delays the additions in progress.
