# ADR-0024: digit-2 — a Fortran HTTP server without a wrapper

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-18 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.5 |

## Context

`CLAUDE.md` 2 assigns digit 2 to Fortran with SQLite. Step P2.5 must
reproduce the reference behaviour of `digit-0` (ADR-0022) and pass
`make contract-digit-2` (ADR-0021). Fortran has no HTTP server library and
no SQLite binding in Alpine. `CLAUDE.md` 4.4 allows a thin wrapper (CGI
through lighttpd, or `socat`) if the digit logic and the database access
stay in Fortran, and requires an ADR for it. `CLAUDE.md` 6.5.4 lists FORD
as the documentation tool for Fortran, with no coverage tool.

## Decision

- **No wrapper.** The HTTP server is written in Fortran 2018
  (`src/http.f90`) on POSIX sockets. The C library is called through
  `bind(C)` interfaces of ISO_C_BINDING (`src/posix.f90`,
  `src/sqlite.f90`); no C source is compiled. Rejected:
  - lighttpd with CGI, and `socat` with `EXEC`: one process per request.
    The counters of `/metrics` could not live in memory as in `digit-0`,
    so every read request would also become a database write, and the
    image would need a second program.
  - FastCGI: as much protocol code as plain HTTP, plus lighttpd.
- **Server shape:**
  - one connection at a time, one request per connection
    (`Connection: close`);
  - the request head must fit 8 KiB and arrive within 500 ms, otherwise
    400 (431 above 8 KiB);
  - after the reply, the write side is shut down and unread bytes are
    drained for at most 200 ms, so a request body never turns into a reset;
  - the listening socket is polled every 200 ms, and a `signal()` handler
    sets a flag on SIGTERM or SIGINT, so a stop takes about 0.2 s.

  A call takes about 0.15 ms with a new connection (about 9 000 calls per
  second). A silent client can delay other callers by about 0.7 s at most,
  below the 2 s call timeout of `CLAUDE.md` 6.1. This is accepted as a
  Medium risk in the threat model.
- **Platform assumptions** (64-bit Linux, identical on amd64 and arm64):
  - socket, poll, signal and shutdown constants are the Linux values;
  - `sockaddr_in` is built as 16 bytes;
  - `d_name` of `struct dirent` is read at byte offset 19, the musl and
    glibc layout.
- **State in a module, not in the program.** The request handler passed
  to the server is a module procedure. Internal procedures of the main
  program needed GCC trampolines, which require an executable stack;
  `-Werror` with `-Wtrampolines` caught this only at code generation. The
  lint stage therefore compiles and links fully instead of
  `-fsyntax-only`.
- **Behaviour:** the contract code (`api_handle`) follows ADR-0022. It is
  a function of (method, path), uses one `digit` row checked against
  `AAAS_DIGIT`, runs the migrations with `schema_migrations`, and keeps
  in-memory counters, JSON logs, `traceparent` parsing and problem details.
  Every edge case measured on `digit-0` answers the same: bodies of any
  size, HEAD, TRACE, unknown methods, query strings.
- **Toolchain:**
  - gfortran 14 compiles with `-std=f2018 -Wall -Wextra -Wpedantic
    -Wimplicit-interface -Wimplicit-procedure -Wconversion -Werror
    -fimplicit-none -fcheck=bounds`; the tests add `-fcheck=all`;
  - fprettify 0.3.7 formats (indent 2, 120 columns), and its warnings fail
    the lint;
  - FORD 7.0.13 and fprettify run from a Python virtual environment, with
    every Python package pinned.
- **Documentation coverage: FORD with `warn: true`.** The doc-coverage
  stage fails on any FORD warning. That covers every undocumented module,
  procedure, interface, argument, type component, constant and local
  variable; locals are documented inline with `!!`. Each C interface is
  its own `interface` block, documented before `interface` and inside the
  procedure, because FORD checks both. `scripts/doc-check.sh` adds a
  `fortran` row: every top-level `module` or `program` needs a `!>`
  comment.
- **Tests:** a small check routine like `digit-0` (67 checks), against
  the real migrations.

## Consequences

- `digit-2` passes the contract test 8/8 with a runtime image of 18.3 MB
  and about 0.8 MiB RAM. No other process runs in the container.
- The constants and `struct dirent` offset bind the service to 64-bit Linux
  (`CLAUDE.md` 6.2 requires only `linux/amd64` and `linux/arm64`).
- Callers must not rely on keep-alive with `digit-2`. Standard HTTP
  clients open a new connection after `Connection: close`; the callers of
  P2.13 (`successor`, `carry`) must be checked against this.
- Medium residual risks are accepted in `THREAT_MODEL.md`: a hand-written
  HTTP parser and one connection at a time.
