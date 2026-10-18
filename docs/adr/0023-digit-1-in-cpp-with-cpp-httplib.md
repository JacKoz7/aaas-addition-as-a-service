# ADR-0023: digit-1 — the digit contract in C++ with cpp-httplib

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-18 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.4 |

## Context

`CLAUDE.md` 2 assigns digit 1 to C++ with SQLite. Step P2.4 must reproduce
the reference behaviour of `digit-0` (ADR-0022) and pass the shared contract
test `make contract-digit-1` (ADR-0021). The C++ standard library has no
HTTP server and no JSON support. Alpine 3.22, the base of every stage image,
packages nlohmann-json and doctest but no C++ HTTP server library. All base
images and packages must be pinned (`CLAUDE.md` 6.2).

## Decision

- **HTTP server: cpp-httplib 0.26.0** (MIT, a single header, released
  2025-08-29). It is added to the toolchain stage with
  `ADD --checksum=sha256:4a42…6da7` from the release tag, so the build
  fails if the file changes; it sits in `/usr/local/include` as a system
  header. It is compiled into the binary, so the runtime image needs only
  `libstdc++`, `libgcc` and `sqlite-libs`. Rejected: libmicrohttpd (a C
  API, which `digit-0` already uses) and Boost.Beast (the whole Boost
  development package in the toolchain for one small server).
- **Threads:** four worker threads, because a keep-alive connection holds
  a worker until it closes and `successor`, `carry` and the saga will keep
  connections open concurrently. The single SQLite connection is shared
  under one mutex in `Api` and the counters are atomic. Idle keep-alive
  connections close after 10 s.
- **TCP_NODELAY is on.** cpp-httplib writes headers and body in separate
  writes; with Nagle's algorithm and the client's delayed ACK every
  keep-alive call took about 40 ms. With TCP_NODELAY a call takes 0.09 ms.
- **Catch-all routes, not a pre-routing handler.** Every method that
  cpp-httplib routes (GET, HEAD through GET, POST, PUT, PATCH, DELETE,
  OPTIONS) is sent to `Api::handle()` by a route on `.*`. A pre-routing
  handler would answer before the library reads the request body; the
  unread body then stayed on the keep-alive connection and the next request
  on it got 400 (measured with a 5 000-byte POST). An error handler turns
  the library's own errors into problem details. TRACE and CONNECT, which
  it parses but cannot route, go through `Api::handle()` too, so they
  answer 405 or 404 like `digit-0`.
- **Two answers outside the contract**, both problem details: a request
  body above 1 KiB answers 413 (the contract has no request bodies, so the
  limit bounds memory), and a request line whose method is not an HTTP
  method answers 400, because cpp-httplib rejects it before routing.
  `digit-0` answers 405 in both cases. No caller sends either, and the
  contract test does not cover them.
- **Code shape** follows ADR-0022: `Api::handle(method, path) → Reply` is
  free of the server library and unit-tested without a network; `Store`
  wraps SQLite in RAII (connection and statements); errors are a
  `StoreError` exception inside the service and 503 replies at the edge.
  JSON bodies and log lines are built with `nlohmann::ordered_json`, so the
  key order matches `digit-0` and log text is always escaped (invalid UTF-8
  is replaced, never thrown).
- **Toolchain:** g++ 14 compiles with C++20 and `-Wall -Wextra -Wpedantic
  -Wconversion -Wshadow -Werror`; clang-format 20 (the `digit-0` style);
  clang-tidy 20 with bugprone, cert, concurrency, cppcoreguidelines, misc,
  modernize, performance, portability and readability, every finding an
  error, and each disabled check justified in `.clang-tidy`.
- **Tests: doctest 2.4.11** (Alpine `doctest-dev`), 9 test cases with
  60 assertions against the real migrations.
- **Documentation coverage: Doxygen**, as for `digit-0`, with
  `EXTRACT_PRIVATE` and `EXTRACT_ANON_NSPACES`: an undocumented private
  member, function in an anonymous namespace or test case fails the stage
  (checked by adding one of each).

## Consequences

- The service passes `make contract-digit-1` (8/8) and shows the same
  answers, metrics, logs and shutdown as `digit-0`; the two edge cases
  above differ and are documented in its README and API.md.
- The cpp-httplib header is fetched from GitHub at build time, which
  depends on the network like every package download; a new version means
  a new checksum in the Dockerfile.
- Runtime image 20.6 MB, about 1.1 MiB RAM; the default `mem_limit` of
  compiled services (64 MB) is kept, as for `digit-0`.
- Native code parses HTTP: the memory-safety risk is mitigated by RAII,
  standard containers, analysers and the pinned, verified library, and
  accepted as Medium (`services/digit-1/docs/THREAT_MODEL.md`).
