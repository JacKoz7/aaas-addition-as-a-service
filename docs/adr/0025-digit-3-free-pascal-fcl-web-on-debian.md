# ADR-0025: digit-3 — Free Pascal with fcl-web on Debian and a distroless runtime

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-18 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.6 |

## Context

`CLAUDE.md` 2 assigns digit 3 to Free Pascal with SQLite. Step P2.6 must
reproduce the reference behaviour of `digit-0` (ADR-0022) and pass
`make contract-digit-3` (ADR-0021). Alpine 3.22, the base of the previous
digit services, does not package Free Pascal. `CLAUDE.md` 6.5.3 names
PasDoc as the documentation tool. PasDoc has no coverage report, and
Free Pascal ships `ptop` as its formatter.

## Decision

- **Toolchain on Debian 13.** The toolchain is
  `debian:trixie-20261005-slim` with Free Pascal 3.2.2, PasDoc 0.16.0,
  xmlstarlet and the SQLite headers, all pinned. `libgcc-14-dev` provides
  `crtbegin.o`. Linking against libc (threads, SQLite) needs it, and its
  directory is added to `/etc/fpc.cfg`, because Debian adds that entry only
  when `gcc` is installed.
- **HTTP: fcl-web `TFPHttpServer`**, shipped with Free Pascal, so no
  wrapper is needed. It is threaded, with one thread per connection, and
  answers one request per connection (`Connection: close`). Two subclasses
  harden it:
  - the connection class sets a 2 s receive timeout on the socket;
  - it reads request bodies up to 64 KiB and leaves larger ones unread
    (the request is answered 413);
  - it keeps the headers the library does not know, so that `traceparent`
    reaches the handler.

  The SQLite connection is shared under a lock in `TApi`, and the counters
  use interlocked operations. The accept loop polls a stop flag set by a
  `SIGTERM` handler every 200 ms (`AcceptIdleTimeout`), then waits up to
  5 s for running connection threads.
- **Response bodies through `ContentStream`.** `TResponse.Content` stores
  the body in a `TStrings` and appends a line ending, while the contract
  bodies must end with the JSON.
- **SQLite through the `sqlite3` unit** (the C API), mirroring
  `digit-0`'s store. `Fail` cannot name a method, because it is an
  intrinsic inside constructors.
- **Formatter: pasfmt 0.7.0.** `ptop` re-indents everything after a class
  with visibility sections, and after constructors and destructors, which
  makes it unusable for Object Pascal. pasfmt has no arm64 release binary,
  so a `pasfmt` stage builds it with Cargo from the commit of the `v0.7.0`
  tag (`--locked`). Only the binary goes into the toolchain.
- **Linter: the compiler.** `fpc -vewnhi -Sewnh` makes warnings, notes and
  hints errors. Range and overflow checks are on (`-Cr -Co`). Hint 5024
  (unused parameter) is off only around the two event handlers whose
  signatures the library fixes.
- **Documentation coverage** has two checks:
  - PasDoc writes `simplexml` for every visibility, and xmlstarlet fails
    on any unit, routine, constant, variable, structure, type or property
    without a description;
  - `tools/implementation-doc-check.awk` covers the unit-level constants
    and variables of the implementation sections, which PasDoc does not
    read.

  Helper routines are declared in the interface sections so that PasDoc
  checks them. `scripts/doc-check.sh` gains a `pascal` row (a comment
  before every `unit` and `program`), and `.awk` files get a header style.
- **Tests: fpcunit** with a small runner that sets the exit code. There are
  8 tests against the real migrations.
- **Runtime: distroless.** The runtime is
  `gcr.io/distroless/cc-debian13:nonroot`, pinned by digest, with
  `libsqlite3.so.0` copied from the toolchain and a static busybox as
  `wget`. The image is 60 MB instead of 143 MB on `debian:trixie-slim`
  (`CLAUDE.md` 6.6). The `cc` variant is needed because glibc loads
  `libgcc_s` when a thread exits. The image has no shell, so the Compose
  healthcheck uses the exec form.

## Consequences

- `digit-3` passes the contract test 8/8. Every edge case measured on
  `digit-0` answers the same, except request bodies above 64 KiB (413).
  A silent connection no longer delays other callers; it only holds its
  own thread for 2 s.
- One thread per connection costs more per call than the single-threaded
  digits: 0.23 ms per call, and 4 000 concurrent calls in 1.46 s. Memory is
  bounded by `mem_limit`. The risk of many open connections is accepted as
  Medium in the threat model.
- The toolchain is larger than the Alpine ones (Free Pascal, plus the Rust
  image used only to build pasfmt). Both are build stages, removed by
  `make prune-stages`.
- Future Free Pascal services (none planned) can reuse this toolchain,
  formatter and coverage check.
