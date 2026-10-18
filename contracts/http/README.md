# HTTP Contracts

| Field | Value |
| --- | --- |
| Document | Contract directory README |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Related | `CLAUDE.md` 4.1, 4.4, [ADR-0021](../../docs/adr/0021-digit-http-contract-and-contract-test.md), [contract tests](../../tests/contract/README.md) |

This directory holds the OpenAPI 3.1 documents of the HTTP/JSON interfaces
of AaaS.

| File | Content | Since |
| --- | --- | --- |
| [`digit.yaml`](digit.yaml) | Contract shared by the ten digit services `digit-0` … `digit-9` (`CLAUDE.md` 4.4): `GET /value`, `GET /next`, `GET /health`, `GET /metrics`, the error format and the request counter `digit_requests_total`. | P2.2 |
| [`redocly.yaml`](redocly.yaml) | Lint configuration: Redocly `recommended-strict` (every warning is an error). | P2.2 |

The OpenAPI document of the public API (`CLAUDE.md` 4.1) is added by the
step that first needs it.

## The digit contract in one table

| Digit d | `GET /value` | `GET /next` |
| --- | --- | --- |
| 0 … 8 | `{digit: d, value: d}` | `{digit: d, next: d + 1, carry: false}` |
| 9 | `{digit: 9, value: 9}` | `{digit: 9, next: 0, carry: true}` |

Both answers come from the service's own SQLite database (seeded by a
migration), never from constants in the code. Errors are
`application/problem+json` (404 unknown path, 405 other method with
`Allow: GET`, 503 database unavailable). The services are internal
(network `aaas-services`, not routed by the gateway), so the contract
declares no authentication (`security: []`, ADR-0021).

## Commands

| Command | What it does |
| --- | --- |
| `make openapi-lint` | Lints every document of this directory with Redocly CLI 2.64.1. Part of `make lint` and of the CI job `contracts`. |
| `make contract-digit-<d>` | Runs the shared contract test against the running `digit-<d>` ([tests/contract](../../tests/contract/README.md)). |
| `make api-md` | Regenerates the HTTP section of every API.md that has `http` markers from the document of its component. |

A change of a document is a separate `contract(contracts)` commit
(`CLAUDE.md` 8.4); an incompatible change of `digit.yaml` raises its major
version and needs all ten digit services to follow in the same step.
