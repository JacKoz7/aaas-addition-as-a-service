<!-- GENERATED FILE: the events section is generated from contracts/events
     by `make api-md` (scripts/service-api.py) and checked by
     `make contracts-check`, the gRPC section from contracts/proto by the
     same tool; the HTTP section is kept in sync by hand with CLAUDE.md 4.3
     (ADR-0016, ADR-0020). Do not add content
     that is not in a contract. The native API documentation is published
     by `make docs`. -->
# API Reference — `successor`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP (port 8080)

| Method | Path | Description | Response |
| --- | --- | --- | --- |
| `POST` | `/v1/next` | `Next` of `CLAUDE.md` 4.3 over HTTP/JSON for the ledger until P3.3 (`TEMPORARY(P3.3)`; gRPC from P2.13): body `{ "n": <integer 0..199997>, "taskId": <lowercase UUID> }`, optional `traceparent` header | `200 { "n": n + 1 }`; `400` malformed body or non-integer `n`; `413` body above 4 KiB; `422` `n` outside the domain or malformed `taskId`; `503` CouchDB or Kafka unavailable (retry the call) |
| `GET` | `/health` | Liveness and readiness | `200 { "status": "ok", "checks": { "database": "ok", "broker": "ok" } }`, `503` when a check fails |
| `GET` | `/metrics` | Prometheus metrics (`successor_calls_total{outcome}`, `successor_call_duration_seconds`, `successor_dependency_failures_total{dependency}`, `successor_build_info`) | `200 text/plain; version=0.0.4` |

Errors use RFC 9457 (`application/problem+json`). Other paths answer `404`,
other methods on these paths `405`.

A call is idempotent per `(taskId, n)`: repeating it returns the same
result and publishes the same event (same `eventId`) again.

## 2. gRPC

Not served yet: the contract below is implemented on port 9090 by P2.13,
when the successor starts querying the digit services and `carry`. Until
P3.3, when the ledger stops calling the successor, `POST /v1/next` above
remains available (`TEMPORARY(P3.3)`).

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
