<!-- GENERATED FILE: the gRPC and events sections are generated from
     contracts/proto and contracts/events by `make api-md`
     (scripts/service-api.py; ADR-0013, ADR-0020) and checked by
     `make contracts-check`; the HTTP section is kept in sync by hand with
     CLAUDE.md 6.1 (the service has no OpenAPI document). Do not add content
     that is not in a contract. The native API documentation is published
     in the portal by `make docs`. -->
# API Reference — `carry`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP (port 8080)

| Method | Path | Description | Response |
| --- | --- | --- | --- |
| `GET` | `/health` | Liveness and readiness: Mnesia readable, broker answering a metadata request within 1 s | `200 { "status": "ok", "checks": { "database": "ok", "broker": "ok" } }`, `503` with `"status": "error"` and the failed check `"error"` |
| `GET` | `/metrics` | Prometheus metrics (`carry_propagations_total{outcome}`, `carry_propagation_duration_seconds`, `carry_digit_calls_total{digit, outcome}`, `carry_dependency_failures_total{dependency}`, `carry_retention_deleted_total`, `carry_build_info`) | `200 text/plain; version=0.0.4` |

Errors use RFC 9457 (`application/problem+json`). Other paths answer `404`,
other methods on these paths `405` with `Allow: GET`. Request bodies are
never read.

## 2. gRPC (port 9090)

Served from carry 0.1.0. Statuses: `INVALID_ARGUMENT` for a request outside
the contract (empty or more than 6 digits, a digit above 9, a position
above the number of digits, a `task_id` that is not a lowercase UUIDv7);
`UNAVAILABLE` when a digit service, Mnesia or the broker failed (retry the
call); `INTERNAL` when a digit service answered outside its contract. A
request body above 4 KiB is refused by the server. The caller's deadline
(`grpc-timeout`) is honoured, capped at 1.8 s.

A call is idempotent per `(task_id, digits, position)`: repeating it
returns the same digits and publishes the same event (same `eventId`)
again, without asking the digit services.

<!-- BEGIN GENERATED: grpc (scripts/service-api.py, do not edit) -->
### `aaas.carry.v1.CarryService`

CarryService is called by the successor service when a digit service reports a carry (digit 9 wrapped to 0). It adds one at the given position, asking the digit service of each visited digit for its successor, and continues upwards while digits keep wrapping.

- Contract: [`carry.proto`](../../../contracts/proto/aaas/carry/v1/carry.proto), package `aaas.carry.v1`.

| RPC | Request | Response | Description |
| --- | --- | --- | --- |
| `Propagate` | `PropagateRequest` | `PropagateResponse` | Propagate adds one at digits[position] and propagates further carries. Example: for 999 + 1, the units digit wraps from 9 to 0 and the successor service sends digits [0, 9, 9] with position 1; the response is [0, 0, 0, 1], that is 1000. A position greater than the number of digits, or a digit outside 0..9, yields the gRPC status INVALID_ARGUMENT. An unreachable digit service yields UNAVAILABLE. |

#### `PropagateRequest`

PropagateRequest carries a number as decimal digits and the position that receives the carry.

| Field | Number | Type | Description |
| --- | --- | --- | --- |
| `digits` | 1 | `repeated uint32` | Decimal digits of the number, least significant first (index 0 is the units digit); each in 0..9, at most 6 digits. |
| `position` | 2 | `uint32` | Index of the digit that receives the carry, in 0..len(digits). When it equals len(digits), a new most significant digit 1 is appended. |
| `task_id` | 3 | `string` | Task identifier (UUIDv7, canonical text form) of the addition, carried into the event aaas.carry.propagated.v1. A missing or malformed task_id yields the gRPC status INVALID_ARGUMENT. |

#### `PropagateResponse`

PropagateResponse carries the number after the carry was applied.

| Field | Number | Type | Description |
| --- | --- | --- | --- |
| `digits` | 1 | `repeated uint32` | Decimal digits of the result, least significant first; one element longer than the request when the carry passed the highest digit. |

<!-- END GENERATED: grpc -->

## 3. Events

<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->
### `aaas.carry.propagated.v1` (produced)

One carry propagated to a higher digit position.

- Producer: `carry`; partitions: 3; message key: `taskId`.
- Schema: [`aaas.carry.propagated.v1.schema.json`](../../../contracts/events/aaas.carry.propagated.v1.schema.json) (`urn:aaas:events:aaas.carry.propagated.v1`), in the envelope of `CLAUDE.md` 4.2.

| Payload field | Required | Description |
| --- | --- | --- |
| `digits` | yes | Decimal digits of the number before the carry, least significant first (index 0 is the units digit). |
| `position` | yes | Index of the digit that received the carry, from 0 to the number of digits; equal to the number of digits when a new most significant digit was created. |
| `result` | yes | Decimal digits after the carry, least significant first: the number plus 10 to the power of position. One element longer than digits when the carry passed the highest digit. |

<!-- END GENERATED: events -->
