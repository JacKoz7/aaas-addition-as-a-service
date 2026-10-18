<!-- GENERATED FILE: the HTTP, gRPC and events sections are generated from
     contracts/http, contracts/proto and contracts/events by `make api-md`
     (scripts/service-api.py; ADR-0013, ADR-0020, ADR-0021) and checked by
     `make contracts-check`. Do not add content that is not in a contract.
     The native API documentation is published in the portal by
     `make docs`. -->
# API Reference — `digit-0`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `digit-0` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP (port 8080)

The service implements the digit contract shared by all ten digit services
for digit 0 (ADR-0021, ADR-0022). The values below are read from the
service's database on every request.

<!-- BEGIN GENERATED: http (scripts/service-api.py, do not edit) -->
- Contract: [`digit.yaml`](../../../contracts/http/digit.yaml), AaaS digit service 1.0.0 (OpenAPI 3.1.0).

| Method | Path | Summary | Responses |
| --- | --- | --- | --- |
| `GET` | `/value` | Value of the digit. | `200` `DigitValue`; `405` `Problem`; `503` `Problem` |
| `GET` | `/next` | Successor of the digit in base 10. | `200` `DigitNext`; `405` `Problem`; `503` `Problem` |
| `GET` | `/health` | Liveness and readiness. | `200` `Health`; `405` `Problem`; `503` `Health` |
| `GET` | `/metrics` | Prometheus metrics. | `200` `text/plain`; `405` `Problem` |

<!-- END GENERATED: http -->

Errors use RFC 9457 (`application/problem+json`). A `traceparent` header is
accepted on every request and continued in the logs.

## 2. gRPC

None: the digit contract is HTTP/JSON (`CLAUDE.md` 4.4); the service opens
no port 9090.

<!-- BEGIN GENERATED: grpc (scripts/service-api.py, do not edit) -->
`digit-0` serves no gRPC contract of `contracts/proto`.

<!-- END GENERATED: grpc -->

## 3. Events

<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->
`digit-0` neither produces nor consumes events.

<!-- END GENERATED: events -->
