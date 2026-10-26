# Dependencies — `carry`

| Field | Value |
| --- | --- |
| Document | Dependencies |
| Component | `carry` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.0 |
| Last Reviewed | 2026-10-26 |

## 1. Upstream (services this service calls)

| Dependency | Contract | Timeout / Retries | Effect of Failure |
| --- | --- | --- | --- |
| `digit-0` … `digit-9` | `GET /next` of [`contracts/http/digit.yaml`](../../../contracts/http/digit.yaml) | 250 ms per attempt, 3 attempts (50 ms, 100 ms and up to 25 ms of jitter), within the call's budget of at most 1.8 s | The call answers `UNAVAILABLE` and records nothing; the caller retries. An answer outside the contract answers `INTERNAL` |
| Redpanda | Kafka produce of `aaas.carry.propagated.v1`, all in-sync replicas | 1 s acknowledgement, 2 producer retries after 100 ms | The call answers `UNAVAILABLE` after recording; the retry republishes the stored event. `/health` reports `broker: error`; brod restarts its client every 5 s |
| Mnesia (embedded) | `carry_propagations`, `carry_migrations` | none (in process) | The call answers `UNAVAILABLE`; `/health` reports `database: error`; a failed start-up exits with status 1 |

Which digit services a call needs: the digit at `position` and every 9
above it, and `digit-0` when the carry passes the highest digit. A carry
at position 1 of `[0, 9, 9]` asks `digit-9` twice and `digit-0` once.

## 2. Downstream (services that call this service)

| Dependant | Interface | Effect of Our Failure |
| --- | --- | --- |
| `successor` (from P2.13b) | `CarryService.Propagate` (gRPC) | Successor steps of numbers ending in 9 fail with `UNAVAILABLE` and are retried by the successor's caller; the addition waits |
| Consumers of `aaas.carry.propagated.v1` | Event | None yet (audit topic) |

## 3. Start-up Dependencies

Compose starts the service after `redpanda` is healthy and
`redpanda-topics` has created the topics (`depends_on`). The digit
services are not start-up dependencies: they are needed per call only.

## 4. Libraries

| Library | Version | Use |
| --- | --- | --- |
| Elixir / Erlang/OTP | 1.20.4 / 28.5 | Language, Mnesia, `:httpc` (inets), `:crypto` |
| `grpc_server` | 1.0.5 | gRPC server on Cowboy 2.20 and ranch 2.3 |
| `grpc` | 1.0.5 | Compile-time dependency of the generated client stub; the client of the tests (with Mint 1.11) |
| `protobuf` | 0.17.1 | Messages of the generated code (`contracts/gen/elixir`, ADR-0020) |
| `brod` | 4.7.0 | Kafka producer (kafka_protocol 4.3, crc32cer 1.1) |
| `credo`, `doctor`, `ex_doc` | 1.7.19, 0.23.0, 0.40.4 | Lint, documentation coverage, API documentation (build stages only) |
