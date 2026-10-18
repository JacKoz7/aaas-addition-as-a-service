# Runbook — `digit-2`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `digit-2` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-18 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=digit-2` |
| Health | `docker compose exec digit-2 wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `docker compose exec digit-2 wget -qO- http://127.0.0.1:8080/metrics` |
| Contract test | `make contract-digit-2` |
| Restart | `docker compose restart digit-2` |
| Rebuild | `make build-digit-2 && make up` |

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
  1. `make ps` — confirm the state of `digit-2`.
  2. `make logs SVC=digit-2` — look for `"level":"error"` lines:
     `cannot read the digit from the database` (SQLite error in `detail`)
     or `the database holds another digit`.
  3. Inspect the database (section 3).
- **Remediation**: a missing or wrong row means the volume was altered;
  recreate it (section 3). Then `docker compose restart digit-2`.
- **Escalation**: Arithmetic Excellence Center (AEC), then PEG (RACI.md).

### 2.2 Service exits at start-up

- **Meaning**: the container restarts or stays `exited` with status 1.
- **Diagnosis**: the last log lines name the cause:
  `unsupported AAAS_BOOTSTRAP` (only `env` exists before P5.2),
  `AAAS_DIGIT must be 0..9`, `AAAS_HTTP_PORT must be 1..65535`,
  `the database cannot be prepared` (the reason in `detail`: the file
  cannot be opened, the migrations directory cannot be read, or a migration
  failed), `the database does not hold the configured digit`, or
  `cannot start the HTTP server` (port taken).
- **Remediation**: correct the environment in `compose/services.yml`, or
  recreate the volume (section 3) when a migration or the seed failed.
- **Escalation**: AEC.

### 2.3 Slow answers

- **Meaning**: calls to the service take up to about 0.7 s instead of a
  fraction of a millisecond.
- **Diagnosis**: the server answers one connection at a time; a client that
  opens a connection and sends nothing holds it for up to 500 ms (plus a
  200 ms drain). Look for a client opening idle connections on the
  `services` network (`docker compose ps`, recent deployments).
- **Remediation**: stop or fix the misbehaving client. No restart of
  `digit-2` is needed.
- **Escalation**: AEC.

### 2.4 Error answers (`outcome="error"`)

- **Meaning**: `digit_requests_total{outcome="error"}` grows: `/value` or
  `/next` answered 503 because the row could not be read.
- **Diagnosis**: as 2.1; the error lines carry the SQLite message.
- **Remediation**: as 2.1. Callers retry 503 answers (the contract marks
  them retryable), so no addition is lost while the service recovers.
- **Escalation**: AEC.

## 3. Database (SQLite, embedded)

- **Inspect**: `docker run --rm -v aaas_digit-2-data:/data alpine:3.22.2 sh -c
  'apk add -q sqlite && sqlite3 /data/digit-2.db "SELECT * FROM digit; SELECT * FROM schema_migrations;"'`
  (the volume name is `<project>_digit-2-data`; see `docker volume ls`).
  Expected: `2|2|3|0` and one migration row.
- **Restore**: the database holds only the seed, so it is recreated rather
  than restored: `docker compose stop digit-2`, `docker volume rm
  aaas_digit-2-data`, `make up`; the migrations recreate the row at start-up.
- **In-flight additions**: a digit call is a single read; a caller whose
  call fails retries it (successor and carry from P2.13), so a restart of
  the service only delays the additions in progress.
