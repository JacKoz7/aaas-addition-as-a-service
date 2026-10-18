<!-- GENERATED FILE: the HTTP, gRPC and events sections are generated from
     contracts/http, contracts/proto and contracts/events by `make api-md`
     (scripts/service-api.py; ADR-0013, ADR-0020, ADR-0021) and checked by
     `make contracts-check`. Do not add content that is not in a contract.
     The native API documentation is published in the portal by
     `make docs`. -->
# API Reference — `digit-4`

| Field | Value |
| --- | --- |
| Document | API Reference |
| Component | `digit-4` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Service Version | 0.1.0 |

## 1. HTTP (port 8080)

The service implements the digit contract shared by all ten digit services
for digit 4 (ADR-0021, ADR-0022, ADR-0026). The values below are read from the
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
accepted on every request and continued in the logs. Connections are
persistent (HTTP/1.1 keep-alive; HTTP/1.0 only with `Connection:
keep-alive`) and close after 10 s of silence. Outside the contract, a
malformed request answers 400, a request body above 64 KiB 413 and a
request head above 8 KiB 431, all as problem details that close the
connection (ADR-0026). `HEAD` is answered like any method other than `GET`
(405), without a body.

## 2. gRPC

None: the digit contract is HTTP/JSON (`CLAUDE.md` 4.4); the service opens
no port 9090.

<!-- BEGIN GENERATED: grpc (scripts/service-api.py, do not edit) -->
`digit-4` serves no gRPC contract of `contracts/proto`.

<!-- END GENERATED: grpc -->

## 3. Events

<!-- BEGIN GENERATED: events (scripts/service-api.py, do not edit) -->
`digit-4` neither produces nor consumes events.

<!-- END GENERATED: events -->
