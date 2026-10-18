# gRPC Contracts

| Field | Value |
| --- | --- |
| Document | Contract directory README |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Related | `CLAUDE.md` 4.3, [ADR-0020](../../docs/adr/0020-grpc-contracts-and-code-generation.md), [generated code](../gen/README.md) |

This directory holds the Protocol Buffers contracts of every synchronous
gRPC call between AaaS services, and the configuration of `buf`, which lints
them, guards them against breaking changes and generates their code.

| File | Content | Since |
| --- | --- | --- |
| [`buf.yaml`](buf.yaml) | buf v2 workspace: one module rooted here; lint rules `STANDARD` and `COMMENTS`; breaking rules `FILE`. | P2.1 |
| [`buf.gen.yaml`](buf.gen.yaml) | Code generation for Go, Rust, Haskell, OCaml, Elixir, C#, Crystal, Zig and Python into [`../gen/<language>/`](../gen/README.md), with local plugins only. | P2.1 |
| `aaas/<service>/v1/<service>.proto` | Contract of one service: package `aaas.<service>.v1`, one `<Name>Service`, its request and response messages. | P2.1 |

## Services

| Package | Service | RPCs | Server | Clients |
| --- | --- | --- | --- | --- |
| [`aaas.validator.v1`](aaas/validator/v1/validator.proto) | `ValidatorService` | `Validate(a, b) → (ok, reason)` | `validator` (Rust, P2.14) | `parser` |
| [`aaas.commutator.v1`](aaas/commutator/v1/commutator.proto) | `CommutatorService` | `Normalize(a, b) → (a, b, swapped)` | `commutator` (Zig, P2.15) | `parser` |
| [`aaas.operator_registry.v1`](aaas/operator_registry/v1/operator_registry.proto) | `OperatorRegistryService` | `Resolve(operator) → (saga, enabled)` | `operator-registry` (Crystal, P2.16) | `parser` |
| [`aaas.idempotency.v1`](aaas/idempotency/v1/idempotency.proto) | `IdempotencyService` | `Claim(key, task_id) → (task_id, existing)`, `MarkFailed(key)` | `idempotency` (Deno, P6.3) | `expression-assembler`, `saga-orchestrator` |
| [`aaas.successor.v1`](aaas/successor/v1/successor.proto) | `SuccessorService` | `Next(n) → (n)` | `successor` (Haskell, P2.13) | `saga-orchestrator` |
| [`aaas.carry.v1`](aaas/carry/v1/carry.proto) | `CarryService` | `Propagate(digits, position) → (digits)` | `carry` (Elixir, P2.13) | `successor` |
| [`aaas.consensus.v1`](aaas/consensus/v1/consensus.proto) | `ConsensusService` | `Vote(task_id, a, b, candidate) → (accepted, result, votes)` | `consensus` (Go, P4.1) | `saga-orchestrator` |

The contracts exist before their servers: each service step implements the
contract published here, and a change it needs is a separate
`contract(contracts)` commit (`CLAUDE.md` 8.4).

## Conventions

- **Layout.** One package per service and major version,
  `aaas.<service>.v<N>`, in the directory `aaas/<service>/v<N>/`. The
  package name cannot contain a hyphen, so `operator-registry` becomes
  `operator_registry` in the package and the directory (ADR-0020).
- **Naming.** `<Name>Service`, and `<Method>Request` / `<Method>Response`
  messages for every RPC, even when a message has the same fields as
  another one (lint rule `RPC_REQUEST_RESPONSE_UNIQUE`).
- **Documentation.** Every service, RPC, message and field has a leading
  comment stating its meaning, its allowed range and the gRPC status codes
  of its failures (lint category `COMMENTS`; the generators copy the
  comments into the generated code).
- **Errors.** A business outcome that is not a failure (out-of-range
  operands, a disabled operator, a rejected vote) is a regular response
  field; gRPC status codes are reserved for calls that could not be
  answered (`INVALID_ARGUMENT`, `NOT_FOUND`, `OUT_OF_RANGE`,
  `UNAVAILABLE`, `DEADLINE_EXCEEDED`, `INTERNAL`).
- **Ranges.** Validated operands and results are `uint32` (0..199 998);
  only `ValidateRequest` uses `uint64`, so that out-of-range input reaches
  the validator instead of being truncated.
- **Compatibility.** `buf breaking` (category `FILE`) rejects any change
  that breaks the wire format or the generated code of an existing package.
  An incompatible change is a new package `v<N+1>`, served next to the old
  one until every client has moved.

## Commands

| Command | What it does |
| --- | --- |
| `make proto-lint` | `buf format` (check) and `buf lint`, then `buf breaking` against `PROTO_AGAINST` (default: the merge base with `main`). Part of `make lint`. |
| `make proto` | Regenerates [`../gen/`](../gen/README.md) in the tool image `aaas/buf:dev` (built from [`infra/buf/`](../../infra/buf/Dockerfile) on first use). |
| `make proto-check` | `proto-lint`, then fails if the committed `../gen/` differs from what `make proto` produces. |
| `make proto-image` | Rebuilds `aaas/buf:dev`, for example after a plugin version changes. |

CI runs `proto-lint` on every push and pull request, and `proto-check`
whenever `contracts/proto/`, `contracts/gen/` or `infra/buf/` changes
(job `proto`).
