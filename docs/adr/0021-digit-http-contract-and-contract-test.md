# ADR-0021: Digit HTTP contract in OpenAPI 3.1 and one black-box contract test

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-18 |
| Deciders | Arithmetic Excellence Center (AEC), Platform Enablement Guild (PEG) |
| Step | P2.2 |

## Context

`CLAUDE.md` 4.4 fixes the HTTP/JSON interface of the ten digit services
(`GET /value`, `GET /next`, `GET /health`, `GET /metrics`) and asks for an
OpenAPI document in `contracts/http/digit.yaml`; step P2.2 adds "a contract
test shared by all digits (`tests/contract/digit.sh`)". `CLAUDE.md` 6.4 asks
for an OpenAPI lint in CI. The ten services will be written in C, C++,
Fortran, Free Pascal, Lua, Dart, Swift, Gleam, D and Racket (P2.3–P2.12),
some behind a CGI or `socat` wrapper, so the test must be black-box. No
digit service exists yet when the test is written. Nothing but Docker may be
required on the host.

## Decision

1. **One OpenAPI 3.1 document for all ten services**, versioned `1.0.0`,
   with a server variable for the digit. Beyond `CLAUDE.md` 4.4 it fixes
   what makes the services interchangeable and observable:
   - closed response schemas (`additionalProperties: false`) for
     `DigitValue` and `DigitNext`; `Health` with a mandatory
     `checks.database`;
   - errors as RFC 9457 problem details: 404 for unknown paths, 405 with
     `Allow: GET` for other methods, 503 when the database cannot be read;
   - the optional `traceparent` header (`CLAUDE.md` 6.1);
   - one counter for all ten services, `digit_requests_total{digit,
     endpoint, outcome}`, so that one dashboard (P7.3) covers them; the
     service-name prefix of other services' metrics (`successor_…`) would
     give ten different names here.
   - `security: []`: the services live on `aaas-services` only and are not
     routed by the gateway; callers are services, and the public edge is
     authenticated at the gateway (P6.2).
2. **Lint with Redocly CLI 2.64.1**, rule set `recommended-strict`
   (warnings fail), in its official multi-arch image: `make openapi-lint`,
   part of `make lint` and the CI job `contracts`.
3. **Black-box contract test in Python**, `tests/contract/digit_contract.py`,
   wrapped by `tests/contract/digit.sh <d> [url]`. It runs in the existing
   tool image `aaas/docs-portal:dev` (Python, PyYAML, jsonschema) on the
   Compose network, and validates responses with the component schemas of
   `digit.yaml` itself (OpenAPI 3.1 schemas are JSON Schema 2020-12), so the
   test cannot drift from the contract. Eight checks, TAP-style output.
   Whether a service reads its digit from SQLite is not observable over
   HTTP; each digit service proves it in its unit tests.
4. **Self-test against test doubles.** `tests/contract/selftest.sh` runs the
   test against `tests/contract/stub/digit_stub.py` (conforming digits 0, 4
   and 9; faulty `/next`; faulty error format) and requires pass and fail
   respectively. CI runs it, so the test is shown to fail before digit
   services rely on it.
5. **Generated HTTP section of API.md.** `scripts/service-api.py` 0.3.0
   renders the operations of a component's OpenAPI document between `http`
   markers (`digit.yaml` for `digit-<d>`, `<component>.yaml` otherwise);
   the API.md template now has generated HTTP, gRPC and events sections.

## Consequences

- Every digit step (P2.3–P2.12) must pass `make contract-digit-<d>` and
  expose `digit_requests_total` with the three labels; the digit template
  of P2.3 implements it once for C.
- A wrapper (CGI, `socat`) must still produce problem details, `Allow` and
  the counter; the contract does not relax for wrapped languages.
- An incompatible change of `digit.yaml` (2.0.0) has to be implemented by
  all ten services in one step.
- `make contract-digits` tests every `services/digit-*` that exists, so it
  grows with Phase 2 without changes.
