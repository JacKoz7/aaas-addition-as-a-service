# ADR-0020: gRPC contracts with buf, local plugins and committed generated code

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-18 |
| Deciders | Platform Enablement Guild (PEG), Arithmetic Excellence Center (AEC), Transaction Integrity Office (TIO), Trust & Identity Board (TIB) |
| Step | P2.1 |

## Context

`CLAUDE.md` 4.3 lists seven gRPC services (validator, commutator,
operator-registry, idempotency, successor, carry, consensus) and requires
`.proto` files in `contracts/proto/aaas/<service>/v1/`, generation with
`buf generate`, `buf lint`, and `buf breaking` in CI. Step P2.1 asks for code
generation for Go, Rust, Haskell, OCaml, Elixir, C#, Crystal, Zig and
Python, before any of the gRPC servers exists.

Constraints:

- Cost 0 and no external APIs besides AWS (`CLAUDE.md` 1.3). buf's remote
  plugins run on the Buf Schema Registry, an external service.
- Nothing but Docker is required on the host; tool images are multi-arch
  (`linux/arm64`, `linux/amd64`).
- Disk budget (`CLAUDE.md` 6.6): the toolchains of nine languages together
  are many gigabytes.
- Every service is built from its own directory (`compose/services.yml`
  uses `context: ../services/<name>`), so it cannot read `contracts/` from
  its build context.
- A protobuf package name cannot contain a hyphen, and buf's
  `PACKAGE_DIRECTORY_MATCH` rule requires the directory to equal the
  package.

## Decision

1. **Layout and naming.** One package per service, `aaas.<service>.v1`, in
   `contracts/proto/aaas/<service>/v1/<service>.proto`, with one
   `<Name>Service` and `<Method>Request`/`<Method>Response` messages. The
   service `operator-registry` uses `operator_registry` in its package
   **and** directory (`aaas/operator_registry/v1/`): this is the only
   deviation from "`<service>` = kebab-case name" of `CLAUDE.md` 2, and
   `CLAUDE.md` 4.3 records it.
2. **buf v2 workspace** in `contracts/proto/` (`buf.yaml`): lint categories
   `STANDARD` and `COMMENTS` (every service, RPC, message and field
   documented), breaking category `FILE`, the strictest one, because the
   generated code depends on file and package names too.
3. **Local plugins only, in one tool image** `aaas/buf:dev`
   (`infra/buf/Dockerfile`). Each plugin is built from source at a pinned
   version in a stage of its own language, and only the binary reaches the
   final Debian bookworm image:

   | Language | Plugin(s) | Runtime of the generated code |
   | --- | --- | --- |
   | Go | `protoc-gen-go` v1.36.12, `protoc-gen-go-grpc` v1.6.2 | `google.golang.org/protobuf`, `google.golang.org/grpc` |
   | Rust | `protoc-gen-prost` 0.5.0, `protoc-gen-tonic` 0.5.0 | `prost` 0.14, `tonic` 0.14 |
   | Haskell | `proto-lens-protoc` 0.9.0.1 (GHC 9.10.3, as `successor`) | `proto-lens-runtime` 0.7; services declared by the server library |
   | OCaml | `protoc-gen-ocaml` (ocaml-protoc-plugin 6.2.0, static) | `ocaml-protoc-plugin` 6.2 |
   | Elixir | `protoc-gen-elixir` (hex `protobuf` 0.17.1, escript on OTP 25), option `plugins=grpc` | hex `protobuf` 0.17, `grpc` |
   | C# | protoc built-in `csharp` and `grpc_csharp_plugin` of Grpc.Tools 2.84.0 | `Google.Protobuf`, `Grpc.Core.Api` / `Grpc.AspNetCore` |
   | Crystal | `protoc-gen-crystal` (protobuf.cr 2.3.1, static) | shard `protobuf` 2.3; messages only |
   | Zig | `protoc-gen-zig` (zig-protobuf 6.0.0, Zig 0.16.0, static) | zig-protobuf 6.0 |
   | Python | protoc built-ins `python` and `pyi` of grpcio-tools 1.84.0, and its `grpc_python` generator through the adapter `protoc-gen-grpc_python` (`infra/buf/protoc_gen_grpc_python.py`), because buf runs every non-stock generator as a plugin executable | `protobuf` ≥ 7.35.1, `grpcio` ≥ 1.84 |

   buf itself (v1.74.0) is built in the Go stage. The image is a developer
   tool, built on first use by `make proto`, not by Compose. It is tagged
   `:dev`, so `make prune-stages` keeps it; only its build cache (the
   language toolchains) is pruned.
4. **Generated code is committed** in `contracts/gen/<language>/`, written
   by `make proto` with `clean: true` (no stale files). `make proto-check`
   regenerates into a scratch copy and fails if the result differs from the
   committed tree. Consequences of the alternative (generating inside every
   service build) were rejected: every language's service image would need
   `buf` and a plugin, and the Haskell and OCaml plugins would be built once
   per service build instead of once.
5. **Consumption by services.** A service that needs generated code gets
   `contracts/` as a named build context (`COPY --from=contracts
   gen/<lang>` in its Dockerfile; `--build-context contracts=…` in its
   Makefile, which the test stages of `parser`, `successor`, `ledger` and
   `expression-assembler` already use for `contracts/events`, and
   `additional_contexts` in Compose for the runtime image). The packaging (Go module, cabal package, dune
   library, mix dependency, crate) is added by the first service of each
   language, in its own step.
6. **Checks.** `scripts/proto.sh` drives everything:
   `make proto-lint` (`buf format` check, `buf lint`, `buf breaking`) runs
   in the small official image `bufbuild/buf:1.74.0` and is part of
   `make lint`; `buf breaking` compares with the same directory at
   `PROTO_AGAINST` (default: the merge base with `main`), extracted with
   `git archive`, and is skipped when that revision has no contracts yet.
   CI runs `proto-lint` on every push and pull request (job `proto`) and
   `proto-check` only when `contracts/proto/`, `contracts/gen/` or
   `infra/buf/` changed, because building `aaas/buf:dev` from scratch
   compiles nine plugins.
7. **Crystal has no gRPC runtime.** protobuf.cr generates messages only and
   no maintained Crystal gRPC server exists. Step P2.16 (`operator-registry`)
   decides how the service is served (a minimal gRPC-over-HTTP/2 server in
   Crystal, or a sidecar) and records it in its own ADR. The same applies to
   Zig (P2.15), where zig-protobuf generates messages and service
   descriptors but no server.
8. **TypeScript is not generated.** `idempotency` (Deno, P6.3) is not in
   the language list of P2.1; it may load the `.proto` files at run time or
   add a TypeScript plugin in its own step.
9. **Generated code is exempt** from the file-header check, the hygiene
   hooks and the linters (`.doc-check-ignore`, `exclude` in
   `.pre-commit-config.yaml`) and marked `linguist-generated`; its
   documentation is the comments of the `.proto` files, which the
   generators copy.

## Consequences

- Every contract change is visible twice in review: in the `.proto` file
  and in the generated diff (collapsed by `linguist-generated`).
- A plugin upgrade is a change of `infra/buf/Dockerfile` followed by
  `make proto-image proto`; CI fails until the regenerated code is
  committed.
- The first build of `aaas/buf:dev` downloads the Go, Rust, Haskell, OCaml,
  Elixir, Crystal and Zig toolchains (several GB, pruned afterwards by
  `make prune-stages`) and takes tens of minutes; the final image (about
  840 MB) stays on disk.
- proto-lens-protoc uses the GHC library at run time, which reads the
  compiler `settings` from the GHC libdir; the image carries those few
  files at the GHC path, not the 1.8 GB of libraries next to them.
- The base images of the plugin stages (Rust, OCaml, Crystal, Elixir) are
  not pruned by `make prune-stages`; they are re-pulled only when the image
  is rebuilt and can be removed with `docker rmi` when disk is short.
- The Zig version of the plugin (0.16.0) is the natural choice for
  `commutator` (P2.15), and protobuf ≥ 7.35.1 / grpcio ≥ 1.84 for the Python
  replica (P4.2); a service may use a different runtime version only if the
  generated code compiles against it.
