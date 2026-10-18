# Contract Tests

| Field | Value |
| --- | --- |
| Owning team | Arithmetic Excellence Center (AEC) |
| Tool | Python 3 with PyYAML and jsonschema, in the image `aaas/docs-portal:dev` |
| Run | `make contract-digit-<d>` (one service), `make contract-digits` (every digit service), `make contract-selftest` (the test itself) |
| Version | 0.1.0 |
| Related | [contracts/http/digit.yaml](../../contracts/http/digit.yaml), [ADR-0021](../../docs/adr/0021-digit-http-contract-and-contract-test.md), `CLAUDE.md` 4.4, 6.4 |

## Role

The ten digit services are written in ten languages and must be
interchangeable for `successor` and `carry`. One black-box test,
[`digit.sh`](digit.sh), checks any of them against the shared contract
[`contracts/http/digit.yaml`](../../contracts/http/digit.yaml). Every digit
step (P2.3 … P2.12) runs it on its service before the step is closed.

## What is checked

[`digit_contract.py`](digit_contract.py) sends real requests and validates
the bodies with the schemas of the OpenAPI document itself, so the test
cannot drift from the contract. For digit `d`:

| # | Check |
| --- | --- |
| 1 | `GET /value` answers 200 `application/json`, schema `DigitValue`, `{digit: d, value: d}` |
| 2 | `GET /next` answers 200 `application/json`, schema `DigitNext`, `next = (d + 1) mod 10`, `carry` only for 9 |
| 3 | `GET /next` answers the same body three times in a row |
| 4 | `GET /value` with a `traceparent` header still answers correctly |
| 5 | `GET /health` answers 200, schema `Health`, `status: ok`, `checks.database: ok` |
| 6 | `GET /metrics` answers `text/plain` with `# TYPE digit_requests_total counter` and samples ≥ 1 for `endpoint="value"` and `endpoint="next"` with `outcome="ok"` |
| 7 | An unknown path answers 404 `application/problem+json`, schema `Problem`, matching `status` |
| 8 | `POST /value` answers 405 `application/problem+json` with `Allow` listing `GET` |

The report is TAP-style (`ok` / `not ok` with the reasons); the exit code is
0 when all checks passed and 1 otherwise. That the digit is read from SQLite
and not hard-coded cannot be observed over HTTP; each digit service proves
it in its own unit tests.

## Running

```sh
make up                      # the digit service must be running
make contract-digit-7        # tests/contract/digit.sh 7
tests/contract/digit.sh 7 http://digit-7:8080   # explicit URL
```

The test runs in a container on the network `aaas-services`
(`AAAS_CONTRACT_NETWORK` overrides it) with the repository mounted
read-only; only Docker is needed on the host.

## Self-test

[`selftest.sh`](selftest.sh) starts test doubles
([`stub/digit_stub.py`](stub/digit_stub.py)) on a private network and
requires the contract test to pass for conforming doubles (digits 0, 4, 9)
and to fail for faulty ones (`/next` off by one; errors as `text/plain`).
CI runs it in the job `contracts`, so the test is proven to fail before any
digit service relies on it passing.
