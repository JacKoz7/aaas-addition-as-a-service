# Runbook — `carry`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-26 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=carry` |
| Health | `docker compose exec carry wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `docker compose exec carry wget -qO- http://127.0.0.1:8080/metrics` |
| One call | `buf curl` from a container on `aaas-services` (README, "Running and testing") |
| Restart | `docker compose restart carry` |
| Rebuild | `make build-carry && make up` |
| Debug log | set `AAAS_LOG_LEVEL: debug` in `compose/services.yml` (one line per call) |

## 2. Alerts

Every alert defined for this service has one section below: meaning,
diagnosis step by step, remediation, escalation. Alerting is introduced in
step P7.4; until then this section lists the failure modes detected by the
Compose healthcheck and the metrics.

### 2.1 Container unhealthy

- **Meaning**: the Compose healthcheck (`GET /health`, every 10 s, 3 s
  timeout) failed five times in a row after the 20 s start period. A
  check is `error` when Mnesia cannot report the size of
  `carry_propagations` (`database`) or the broker does not answer a
  metadata request for `aaas.carry.propagated.v1` within 1 s (`broker`).
- **Diagnosis**:
  1. `make ps` — confirm the state of `carry` and `redpanda`.
  2. The `checks` object of `/health` names the failing dependency.
  3. `make logs SVC=carry` — `brod_client … is terminating` lines mean the
     broker is unreachable; brod restarts the client every 5 s.
  4. Database: free space of the `carry-data` volume
     (`docker system df -v`); Mnesia lines in the log.
- **Remediation**: restore Redpanda (`docker compose up -d redpanda`);
  the client reconnects by itself, no restart of `carry` is needed. For
  Mnesia, `docker compose restart carry`.
- **Escalation**: Arithmetic Excellence Center (AEC), then PEG for
  Redpanda (RACI.md).

### 2.2 Calls failing with UNAVAILABLE

- **Meaning**: `carry_propagations_total{outcome="unavailable"}` and
  `carry_dependency_failures_total{dependency}` grow; the log has
  `"msg":"carry not propagated"` with `"code":"unavailable"` and a
  `detail` starting with `digit-N:`, `database:` or `broker:`. The caller
  retries; additions slow down but stay correct.
- **Diagnosis**:
  1. The `dependency` label or the `detail` prefix.
  2. `digit-N`: `make ps`; `make contract-digit-N`; `"msg":"digit service
     unavailable"` lines give the last error (`nxdomain` = container
     stopped, `timeout`, `HTTP 503` = its database).
  3. `broker`: `docker compose exec redpanda rpk cluster health`.
  4. `database`: as in 2.1.
- **Remediation**: restart the failing dependency; recorded calls are
  replayed by the caller's retry (same event, same `eventId`).
- **Escalation**: AEC (digit services), PEG (Redpanda).

### 2.3 Calls failing with INTERNAL

- **Meaning**: `carry_propagations_total{outcome="internal"}` grows: a
  digit service answered outside `contracts/http/digit.yaml` (a 4xx, a
  body for another digit or a successor outside 0..9), or `digit-0`
  reported a carry for the successor of 0. A sum would be wrong if the
  answer were used, so the call fails instead.
- **Diagnosis**: the `detail` of the log line names the digit service;
  run `make contract-digit-N` for it; inspect its database row
  (`RUNBOOK.md` of that service).
- **Remediation**: fix the digit service; the caller's retry then
  succeeds. Never edit this service to accept the answer.
- **Escalation**: AEC; this is a correctness incident (postmortem).

### 2.4 Calls refused with INVALID_ARGUMENT

- **Meaning**: `carry_propagations_total{outcome="invalid_argument"}`
  grows: a caller sends requests outside `carry.proto` (`detail` names the
  rule). The service is healthy; the caller has a bug.
- **Remediation**: fix the caller (from P2.13b, `successor`).
- **Escalation**: AEC.

### 2.5 Memory near the limit

- **Meaning**: `docker stats` shows `carry` near 128 MiB (measured peak
  under load: 50 MiB, CAPACITY.md).
- **Diagnosis**: the number of connections (`/metrics` has none; use
  `docker compose exec carry netstat -tn`); a growing Mnesia table does
  not use memory (`disc_only_copies`).
- **Remediation**: `docker compose restart carry`; report the load
  pattern to AEC for a capacity review.
- **Escalation**: AEC, then OSG.

## 3. Routine Operations

| Operation | Procedure |
| --- | --- |
| Inspect the propagation log | Stop the service first (dets is single-writer), then open `/data/mnesia/carry_propagations.DAT` with `:dets.open_file/2` in a container of the `test` image |
| Empty the log | `docker compose rm -sf carry && docker volume rm aaas_carry-data && make up` (the schema and migration 0001 are recreated) |
| Change the retention | `AAAS_RETENTION_HOURS` in `compose/services.yml`; the next hourly run applies it |
| Upgrade | Rebuild and restart; new migrations run at start-up |

## 4. Shutdown

SIGTERM (`docker compose stop carry`) suspends the gRPC listener, waits up
to 5 s for the calls in progress (`"msg":"gRPC calls drained"`), stops the
listeners and Mnesia and exits with status 0 (measured: 1.7 s for
`docker compose stop`, 3 ms from `SIGTERM received` to `stopped`).
