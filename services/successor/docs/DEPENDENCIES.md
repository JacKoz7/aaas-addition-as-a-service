# Dependencies — `successor`

| Field | Value |
| --- | --- |
| Document | Dependency Register |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.1 |
| Last Reviewed | 2026-10-26 |

## 1. Upstream (this service depends on)

| Dependency | Kind | Contract | Effect of Failure |
| --- | --- | --- | --- |
| CouchDB (`successor-db`) | Database (container) | Private schema in `migrations/` | At startup: migrations retried for 60 s, then exit 1. Later: `database` check fails; calls answer 503 after three attempts of 250 ms; the caller retries |
| Redpanda | Event bus | Kafka protocol, `redpanda:9092`; produces [`aaas.successor.called.v1`](../../../contracts/events/aaas.successor.called.v1.schema.json) | `broker` check fails; calls answer 503 after the 1 s message timeout; the caller retries |
| `digit-0` … `digit-9` (AEC) | HTTP/JSON, `GET /next` of the units digit, once per first call | [`contracts/http/digit.yaml`](../../../contracts/http/digit.yaml) | The calls whose units digit is served by the failed service answer 503 / `UNAVAILABLE` after three attempts of 250 ms (`successor_dependency_failures_total{dependency="digit-<d>"}`); other calls are not affected; the caller retries. A reply outside the contract (another digit, a successor outside 0..9) counts as a failure |
| `carry` (AEC) | gRPC `aaas.carry.v1.CarryService/Propagate` on `carry:9090`, for first calls whose units digit is 9 | [`carry.proto`](../../../contracts/proto/aaas/carry/v1/carry.proto) | Those calls answer 503 / `UNAVAILABLE` within 2 s (`dependency="carry"`); the connection is re-established every 100–200 ms; the caller retries. Carry's own digit calls are its dependency (its DEPENDENCIES.md) |

## 2. Downstream (depends on this service)

| Dependant | Kind | Contract | Effect of Our Failure |
| --- | --- | --- | --- |
| `ledger` (P1.7, until P3.3) | Caller of `POST /v1/next` | API.md | Additions stop counting; they continue when the service is back |
| `saga-orchestrator` (from P3.3) | Caller of `Next` (gRPC, port 9090) | API.md, `contracts/proto/aaas/successor/v1/` | Activity retries; the workflow waits |
| Audit (no consumer yet) | `aaas.successor.called.v1` | [schema](../../../contracts/events/aaas.successor.called.v1.schema.json) | None |
| Compose healthcheck | `GET /health` | API.md | The container is reported unhealthy |

## 3. Build-Time Dependencies

| Dependency | Version | Licence |
| --- | --- | --- |
| `haskell` (build image) | `9.10.3-slim-bookworm` (GHC 9.10.3, cabal 3.14) | BSD-3-Clause (GHC), MIT (image) |
| `debian` (runtime image) | `bookworm-20251020-slim` | per-package licences (DFSG) |
| `couchdb` (database image base) | 3.5.1 | Apache-2.0 |
| librdkafka (`librdkafka-dev`, `librdkafka1`) | 2.0.2-1 | BSD-2-Clause |
| aeson | 2.3.2.0 | BSD-3-Clause |
| warp, wai | 3.4.16, 3.2.5 | MIT |
| wai-extra (tests) | 3.1.18 | MIT |
| http-client, http-types | 0.7.19, 0.12.6 | MIT, BSD-3-Clause |
| hw-kafka-client | 5.3.0 | MIT |
| prometheus-client | 1.1.2 | Apache-2.0 |
| grapesy, grpc-spec (gRPC server and client) | 1.2.1, 1.1.0 | BSD-3-Clause |
| http2, tls, network (grapesy transport) | 5.4.6, 2.4.9, 3.2.9.0 | BSD-3-Clause |
| proto-lens, proto-lens-runtime, lens-family (generated messages) | 0.7.1.7, 0.7.0.8, 2.1.3 | BSD-3-Clause |
| lens (via grapesy) | 5.3.6 | BSD-2-Clause |
| stm | 2.5.3.1 | BSD-3-Clause |
| protoc, well-known `.proto` files (toolchain only: `protobuf-compiler`, `libprotobuf-dev`) | 3.21.12-3+deb12u1 | BSD-3-Clause |
| Generated messages `contracts/gen/haskell` (proto-lens-protoc 0.9.0.1, ADR-0020) | repository | MIT |
| text, bytestring, time, unix | 2.1.3, 0.12.2.0, 1.12.2, 2.8.7.0 | BSD-2-Clause / BSD-3-Clause |
| random, scientific | 1.2.1.3, 0.3.9.0 | BSD-3-Clause |
| hspec (tests) | 2.11.18 | MIT |
| ormolu (lint) | 0.8.0.2 | BSD-3-Clause |
| hlint (lint) | 3.10 | BSD-3-Clause |
| doctest (tests) | 0.25.0.2 | MIT |
| jsonschema and its tree (contract test) | 4.26.0 (versions of the documentation image) | MIT |

Every Haskell dependency is pinned by `cabal.project.freeze` (194
packages) at the `index-state` of `cabal.project`. The `snappy` flag of
grpc-spec is off (`cabal.project`): messages are sent uncompressed and no
snappy C library is needed.
