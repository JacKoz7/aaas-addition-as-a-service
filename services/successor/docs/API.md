<!-- GENERATED FILE: the events section is generated from contracts/events
     by `make api-md` (scripts/service-api.py) and checked by
     `make contracts-check`, the gRPC section from contracts/proto by the
     same tool; the HTTP section and the status list of the gRPC section
     are kept in sync by hand with CLAUDE.md 4.3 (ADR-0016, ADR-0020,
     ADR-0033). Do not add content
     that is not in a contract. The native API documentation is published
     by `make docs`. -->
# API Reference — `successor`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Service Version | 0.2.0 |

## 1. HTTP (port 8080)

| Method | Path | Description | Response |
| --- | --- | --- | --- |
| `POST` | `/v1/next` | `Next` of `CLAUDE.md` 4.3 over HTTP/JSON for the ledger until P3.3 (`TEMPORARY(P3.3)`; the gRPC form is section 2): body `{ "n": <integer 0..199997>, "taskId": <lowercase UUIDv7> }`, optional `traceparent` header | `200 { "n": n + 1 }`; `400` malformed body or non-integer `n`; `413` body above 4 KiB; `422` `n` outside the domain or a `taskId` that is not a lowercase UUIDv7; `503` a digit service, `carry`, CouchDB or Kafka unavailable (retry the call) |
| `GET` | `/health` | Liveness and readiness | `200 { "status": "ok", "checks": { "database": "ok", "broker": "ok" } }`, `503` when a check fails |
| `GET` | `/metrics` | Prometheus metrics (`successor_calls_total{outcome}`, `successor_call_duration_seconds`, `successor_dependency_failures_total{dependency}`, `successor_build_info`) | `200 text/plain; version=0.0.4` |

Errors use RFC 9457 (`application/problem+json`). Other paths answer `404`,
other methods on these paths `405`.

A call is idempotent per `(taskId, n)`: repeating it returns the same
result and publishes the same event (same `eventId`) again. Both
interfaces compute `n + 1` through the digit services and, for a units
digit 9, `carry`.

## 2. gRPC (port 9090)

Served from successor 0.2.0, plain HTTP/2 without TLS. Statuses:
`INVALID_ARGUMENT` when `task_id` is not a lowercase UUIDv7;
`OUT_OF_RANGE` when `n` is above 199 997; `UNAVAILABLE` when a digit
service, `carry`, CouchDB or Kafka failed, or while the service stops
(retry the call). A `traceparent` custom metadata entry is continued.
Other methods answer `UNIMPLEMENTED`.

<!-- BEGIN GENERATED: grpc (scripts/service-api.py, do not edit) -->
### `aaas.successor.v1.SuccessorService`

SuccessorService computes the successor of a natural number by querying the digit services and, on a carry, the carry service. The saga calls it b times to compute a + b.

- Contract: [`successor.proto`](../../../contracts/proto/aaas/successor/v1/successor.proto), package `aaas.successor.v1`.

| RPC | Request | Response | Description |
| --- | --- | --- | --- |
| `Next` | `NextRequest` | `NextResponse` | Next returns n + 1. An n outside 0..199 997 yields the gRPC status OUT_OF_RANGE (the largest possible sum is 99 999 + 99 999 = 199 998). An unreachable digit or carry service yields UNAVAILABLE. |

#### `NextRequest`

NextRequest carries the number whose successor is requested and the task the call belongs to.

| Field | Number | Type | Description |
| --- | --- | --- | --- |
| `n` | 1 | `uint32` | Natural number in 0..199 997. |
| `task_id` | 2 | `string` | Task identifier (UUIDv7, canonical text form). An addition asks for the successor of each value from a to a + b - 1 exactly once, so (task_id, n) identifies a call: a retried call is answered from the call log without a second log entry or event (ADR-0016). A missing or malformed task_id yields the gRPC status INVALID_ARGUMENT. |

#### `NextResponse`

NextResponse carries the successor.

| Field | Number | Type | Description |
| --- | --- | --- | --- |
| `n` | 1 | `uint32` | n + 1, in 1..199 998. |

<!-- END GENERATED: grpc -->

## 3. Events

<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->
### `aaas.successor.called.v1` (produced)

One computation of n + 1 by the successor service.

- Producer: `successor`; partitions: 3; message key: `taskId`.
- Schema: [`aaas.successor.called.v1.schema.json`](../../../contracts/events/aaas.successor.called.v1.schema.json) (`urn:aaas:events:aaas.successor.called.v1`), in the envelope of `CLAUDE.md` 4.2.

| Payload field | Required | Description |
| --- | --- | --- |
| `n` | yes | Argument of the call: a natural number from 0 to 199 997, so that the result is a possible sum. |
| `result` | yes | The successor of n, always n + 1. |

<!-- END GENERATED: events -->
