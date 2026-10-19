# Runbook — `digit-6`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `digit-6` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-19 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=digit-6` |
| Health | `docker compose exec digit-6 /usr/local/bin/wget -qO- http://127.0.0.1:8080/health` (no shell in the image) |
| Metrics | `docker compose exec digit-6 /usr/local/bin/wget -qO- http://127.0.0.1:8080/metrics` |
| Contract test | `make contract-digit-6` |
| Restart | `docker compose restart digit-6` |
| Rebuild | `make build-digit-6 && make up` |

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
  1. `make ps` — confirm the state of `digit-6`.
  2. `make logs SVC=digit-6` — look for `"level":"error"` lines:
     `cannot read the digit from the database` (SQLite error in `detail`)
     or `the database holds another digit`.
  3. Inspect the database (section 3).
- **Remediation**: a missing or wrong row means the volume was altered;
  recreate it (section 3). Then `docker compose restart digit-6`.
- **Escalation**: Arithmetic Excellence Center (AEC), then PEG (RACI.md).

### 2.2 Service exits at start-up

- **Meaning**: the container stays `exited` with status 1 (the digit
  services have no restart policy).
- **Diagnosis**: the last log line names the cause:
  - `unsupported AAAS_BOOTSTRAP` (only `env` exists before P5.2),
    `AAAS_DIGIT must be 0..9` or `AAAS_HTTP_PORT must be 1..65535`;
  - `the database cannot be prepared`, with the reason in `detail`:
    `cannot open the database`, `cannot read the migrations directory`,
    `cannot read migration …` or `migration … failed` (the SQLite message
    included);
  - `the database does not hold the configured digit`;
  - `cannot start the HTTP server` (`detail`: the port and the system
    error, for example `Address already in use`).
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

### 2.4 Connections refused (`connection limit reached`)

- **Meaning**: `"level":"warn"` lines `connection limit reached; connection
  closed`: 256 connections are open at once, and new ones are closed on
  accept. Callers see a closed connection and retry.
- **Diagnosis**:
  1. Count the lines: `make logs SVC=digit-6 | grep -c 'connection limit'`.
  2. Find the client holding connections (`docker stats`, the callers'
     logs). Idle connections close after 10 s, so a lasting excess means a
     client opens connections faster than it closes them.
- **Remediation**: fix or stop the offending client. The limit protects
  the 64 MB memory limit; it is not raised without a capacity review
  (CAPACITY.md).
- **Escalation**: AEC, then the owner of the offending client.

`accept failed` warnings (for example too many open files) follow the same
diagnosis; the server retries the accept every 200 ms. `cannot start a
connection thread` means the system refused a thread; the connection is
closed and the caller retries.

### 2.5 Container stopped by the memory limit (`OOMKilled`)

- **Meaning**: `docker inspect aaas-digit-6-1 --format '{{.State.OOMKilled}}'`
  prints `true` and the container is `exited`. The service bounds what a
  client can make it hold (heads of 8 KiB, bodies of 64 KiB, 256
  connections with 256 KiB thread stacks, 16 KiB read while closing); a
  flood of 512 concurrent connections with 1 MB heads, repeated three
  times, stayed at 10.1 MiB (CAPACITY.md), so an OOM kill points to a
  defect.
- **Diagnosis**: the last log lines before the stop; `docker stats` of the
  clients on the `services` network.
- **Remediation**: `make up` starts it again; open an incident and keep
  the logs.
- **Escalation**: AEC.

## 3. Database (SQLite, embedded)

- **Inspect**: `docker run --rm -v aaas_digit-6-data:/data alpine:3.22.2 sh -c
  'apk add -q sqlite && sqlite3 /data/digit-6.db "SELECT * FROM digit; SELECT * FROM schema_migrations;"'`
  (the volume name is `<project>_digit-6-data`; see `docker volume ls`).
  Expected: `6|6|7|0` and one migration row.
- **Restore**: the database holds only the seed, so it is recreated rather
  than restored: `docker compose stop digit-6`, `docker volume rm
  aaas_digit-6-data`, `make up`; the migrations recreate the row at start-up.
- **In-flight additions**: a digit call is a single read; a caller whose
  call fails retries it (successor and carry from P2.13), so a restart of
  the service only delays the additions in progress.
