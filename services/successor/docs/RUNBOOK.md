# Runbook — `successor`

| Field | Value |
| --- | --- |
| Document | Operational Runbook |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.1 |
| Last Reviewed | 2026-10-26 |

## 1. Quick Reference

| Item | Command |
| --- | --- |
| State | `make ps` |
| Logs | `make logs SVC=successor` |
| Health | `docker compose exec successor wget -qO- http://127.0.0.1:8080/health` |
| Metrics | `GET /metrics` on port 8080 |
| One gRPC call | `docker run --rm --network aaas-services -v "$PWD/contracts/proto:/proto:ro" bufbuild/buf:1.74.0 curl --schema /proto --protocol grpc --http2-prior-knowledge -d '{"n":199,"taskId":"<uuidv7>"}' http://successor:9090/aaas.successor.v1.SuccessorService/Next` |
| Restart | `docker compose restart successor` |
| Rebuild | `make build-successor && make up` |

## 2. Alerts

Every alert defined for this service has one section below: meaning,
diagnosis step by step, remediation, escalation. Alerting is introduced in
step P7.4; until then this section lists the failure modes detected by the
Compose healthcheck.

### 2.1 Container unhealthy

- **Meaning**: the Compose healthcheck (`GET /health`, every 10 s, 3 s
  timeout) failed five times in a row after the 20 s start period;
  dependants that wait with `condition: service_healthy` do not start.
- **Diagnosis**:
  1. `make ps` — confirm the state of `successor`.
  2. `make logs SVC=successor` — look for `level":"error"` entries.
  3. Check the `checks` object of the last `/health` response for the failing
     dependency.
- **Remediation**: fix the failing dependency, then
  `docker compose restart successor`.
- **Escalation**: Arithmetic Excellence Center (AEC), then PEG (RACI.md).

The checks of `/health`: `database` (`GET /successor_calls` answers 200)
and `broker` (a metadata request for `aaas.successor.called.v1` answers
within 1 s).

### 2.2 Calls failing with 503

- **Meaning**: `successor_calls_total{outcome="failed"}` and
  `successor_dependency_failures_total{dependency}` grow; the log has
  `"msg":"successor call failed"` with `dependency` (`couchdb`, `kafka`,
  `carry` or `digit-0` … `digit-9`) and `error`. The caller receives a 503
  problem (HTTP) or `UNAVAILABLE` (gRPC) and retries; additions slow down
  but stay correct. `/health` stays green for a digit or carry outage: the
  service itself works, and the failing dependency has its own health
  check.
- **Diagnosis**:
  1. `dependency` of the log line.
  2. CouchDB: `make ps`, `docker compose logs successor-db`, free space of
     the `successor-data` volume (`docker system df -v`).
  3. Kafka: `docker compose exec redpanda rpk cluster health`; librdkafka
     lines in the log (`"msg":"librdkafka"`).
  4. `digit-<d>`: `make ps`, `make contract-digit-<d>`; an `error` such as
     `the reply is for digit 4` means the service answers outside its
     contract (a wrong row in its database).
  5. `carry`: `make ps`, `make logs SVC=carry` (its own failures name the
     digit service it could not reach); `no answer within 2 s` means
     carry did not answer in time, `GrpcInvalidArgument` a defect of the
     request (escalate to AEC).
- **Remediation**: restore the dependency; nothing else is needed: the
  connection to carry is re-established within 200 ms, and retried calls
  are answered from the call log.
- **Escalation**: PEG for Redpanda, AEC otherwise.

### 2.3 Many replayed calls

- **Meaning**: `successor_calls_total{outcome="replayed"}` grows fast: the
  caller retries calls that had succeeded, usually because its timeout is
  shorter than the call latency.
- **Diagnosis**: compare `successor_call_duration_seconds` with the
  caller's timeout; check CouchDB latency.
- **Remediation**: fix the slow dependency or the caller's timeout.
- **Escalation**: TIO (owner of the caller).

### 2.4 Arguments rejected

- **Meaning**: `successor_calls_total{outcome="rejected"}` grows; the log
  has `"argument outside the domain"`. A caller asked for the successor of
  a number outside `0..199997`, or sent a malformed body or a `taskId`
  that is not a lowercase UUIDv7 (`INVALID_ARGUMENT` over gRPC, not
  logged): a defect of the caller.
- **Escalation**: TIO.

## 3. Database (CouchDB, container)

CouchDB is reachable only on the `data` network; use `curl` inside its
container:

```sh
docker compose exec successor-db curl -s -u successor:"$SUCCESSOR_DB_PASSWORD" \
  http://127.0.0.1:5984/successor_calls
docker compose exec successor-db curl -s -u successor:"$SUCCESSOR_DB_PASSWORD" \
  "http://127.0.0.1:5984/successor_calls/_design/call_log/_view/by_task?startkey=%5B%22<taskId>%22%5D&endkey=%5B%22<taskId>%22,%7B%7D%5D"
```

- **Backup**: stop `successor` and copy the volume `aaas_successor-data`
  (`/opt/couchdb/data`); restore by copying it back.
- **Loss of the database**: the call log of past additions is gone; the
  migrations recreate the databases at the next start. A call of an
  addition in progress is then logged again and its event published with a
  new `eventId` (consumers deduplicate by `eventId`; the audit topic has
  no consumer yet).
- **In-flight additions**: a call is answered only after it is logged and
  published, so stopping the service at any moment leaves the caller to
  retry the same call, which is safe. On SIGTERM the service stops
  accepting HTTP connections, answers new gRPC calls with `UNAVAILABLE`
  and gives the calls in progress up to 8 s.
