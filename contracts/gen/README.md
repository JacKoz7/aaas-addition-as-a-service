# Generated gRPC Code

| Field | Value |
| --- | --- |
| Document | Contract directory README |
| Owning Team | Platform Enablement Guild (PEG) |
| Classification | INTERNAL |
| Related | `CLAUDE.md` 4.3, [ADR-0020](../../docs/adr/0020-grpc-contracts-and-code-generation.md), [gRPC contracts](../proto/README.md), [tool image](../../infra/buf/Dockerfile) |

Everything below this directory, except this README, is **generated** from
[`../proto/`](../proto/README.md) by `make proto` and must never be edited
by hand. `make proto-check` (CI job `proto`) fails when the committed files
differ from the generator output, so a contract change and its regenerated
code always land in the same commit.

| Directory | Layout | Generator | Runtime needed by the consuming service |
| --- | --- | --- | --- |
| `go/` | `aaas/<service>/v1/<service>.pb.go`, `<service>_grpc.pb.go`; import path `github.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/<service>/v1` (package `<service>v1`) | protoc-gen-go v1.36.12, protoc-gen-go-grpc v1.6.2 | `google.golang.org/protobuf` v1.36, `google.golang.org/grpc` ≥ 1.64 |
| `rust/` | `aaas/<service>/v1/aaas.<service>.v1.rs` (messages) and `.tonic.rs` (services), to be pulled in with `include!` | protoc-gen-prost 0.5.0, protoc-gen-tonic 0.5.0 | `prost` 0.14, `tonic` 0.14 |
| `haskell/` | `Proto/Aaas/<Service>/V1/<Service>.hs` and `<Service>_Fields.hs` | proto-lens-protoc 0.9.0.1 | `proto-lens-runtime` 0.7 (services are declared by the server library) |
| `ocaml/` | `<service>.ml`, one module per proto file, with service signatures | protoc-gen-ocaml (ocaml-protoc-plugin 6.2.0) | `ocaml-protoc-plugin` 6.2 |
| `elixir/` | `aaas/<service>/v1/<service>.pb.ex`, messages and `GRPC.Service` modules | protoc-gen-elixir (hex `protobuf` 0.17.1, `plugins=grpc`) | hex `protobuf` 0.17, `grpc` |
| `csharp/` | `<Service>.cs` (messages) and `<Service>Grpc.cs` (services); namespace `Aaas.<Service>.V1` | protoc 35.1 built-in, grpc_csharp_plugin of Grpc.Tools 2.84.0 | `Google.Protobuf`, `Grpc.Core.Api` (for example through `Grpc.AspNetCore`) |
| `crystal/` | `<service>.pb.cr`, messages only, modules `Aaas::<Service>::V1` | protoc-gen-crystal (protobuf.cr 2.3.1) | shard `protobuf` 2.3 |
| `zig/` | `aaas/<service>/v1.pb.zig`, messages and a service interface type | protoc-gen-zig (zig-protobuf 6.0.0) | zig-protobuf 6.0 on Zig 0.16.0 |
| `python/` | `aaas/<service>/v1/<service>_pb2.py`, `_pb2.pyi`, `_pb2_grpc.py`; absolute imports from the package `aaas` | grpcio-tools 1.84.0 (protoc 35.1) | `protobuf` ≥ 7.35.1, < 8; `grpcio` ≥ 1.84 |

## Using the code in a service

Services are built from their own directory, so a service receives this tree
as a named build context and copies only its language:

```dockerfile
# Dockerfile of the service
COPY --from=contracts gen/go/ /src/gen/
```

```make
# services/<name>/Makefile (test, lint and doc stages)
DOCKER_BUILD := docker build --build-context contracts=$(CURDIR)/../../contracts …
```

and, for the runtime image built by Compose, `additional_contexts:
{contracts: ../contracts}` in `compose/services.yml`. The packaging (Go
module, crate, cabal or dune library, mix dependency) is added by the first
service of each language (ADR-0020).

## Verification done when the tree was created (P2.1)

- `make proto-check`: the tree equals the generator output.
- Go: `go vet` and `go build` of every package against
  `google.golang.org/grpc` v1.84.0 and `google.golang.org/protobuf`
  v1.36.12.
- Python: every `_pb2` and `_pb2_grpc` module imports with `protobuf`
  7.36.2 and `grpcio` 1.84.0, and a message round-trips through its wire
  format.
- The other languages are compiled by the steps of their first service
  (Elixir in P2.13a, Haskell in P2.13b, Rust in P2.14, Zig in P2.15, Crystal in
  P2.16, OCaml in P2.17, C# in P6.3).
