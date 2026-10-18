# ADR-0022: digit-0 — reference implementation of the digit contract in C

| Field | Value |
| --- | --- |
| Status | Accepted |
| Date | 2026-10-18 |
| Deciders | Arithmetic Excellence Center (AEC) |
| Step | P2.3 |

## Context

`CLAUDE.md` 2 assigns digit 0 to C with SQLite, and step P2.3 makes it the
reference implementation of `contracts/http/digit.yaml` (ADR-0021) for the
nine other digit services. C has no HTTP server in its standard library;
`CLAUDE.md` 4.4 requires the value and successor to be read from the
service's own SQLite database, seeded by a migration, never hard-coded.
`CLAUDE.md` 6.5.4 requires 100% documentation coverage, and C has no
dedicated coverage tool.

## Decision

- **HTTP server: libmicrohttpd 1.0.1** (GNU, LGPL-2.1+, dynamically linked
  from Alpine), in its single internal thread
  (`MHD_USE_INTERNAL_POLLING_THREAD`). A request takes about 0.07 ms, so one
  thread is enough, and the SQLite connection and the counters need no
  locks. No wrapper (CGI, `socat`) is needed for C.
- **The contract is a pure function.** `api_handle(ctx, method, path,
  &reply)` in `src/api.c` implements every rule of the contract and is
  unit-tested without a network; `src/main.c` only bridges libmicrohttpd to
  it. The other digit services are encouraged to keep this split.
- **Reference behaviour** that the other nine services reproduce:
  - one table `digit` with exactly one row, seeded by
    `migrations/0001_digit.sql`, read on every request;
  - `AAAS_DIGIT` names the expected digit; the service refuses to start, and
    answers 503 (`/health` included), when the row is missing, duplicated or
    names another digit;
  - migrations `NNNN_*.sql` applied in lexical order, each once, in one
    transaction with its record in `schema_migrations`;
  - request bodies are never read; problem details for 404, 405 (`Allow:
    GET`) and 503;
  - metrics `digit_requests_total{digit,endpoint,outcome}` (all four samples
    from the start, value 0) and `digit_build_info{digit,version}`;
  - logs as in `CLAUDE.md` 6.1, `taskId` null (a digit call has no task),
    `traceId`/`spanId` from `traceparent`; one debug line per request,
    `AAAS_LOG_LEVEL=info` by default;
  - SIGTERM stops the server and closes the database (measured: 231 ms).
- **No OTLP export yet.** Like the services of Phase 1, the service continues
  the caller's trace in its logs; spans and the export to the collector come
  with the instrumentation step P7.2.
- **Toolchain in one Alpine image:** GCC 14 compiles (C17, all warnings as
  errors, `-Wpedantic`); clang-format 20 (LLVM style, 120 columns) and
  clang-tidy 20 (bugprone, cert, clang-analyzer, misc, performance,
  portability; every finding an error) lint; ignored return values are
  explicit `(void)` casts (`cert-err33-c`).
- **Documentation coverage: Doxygen.** `EXTRACT_STATIC`, `EXTRACT_PRIVATE`,
  `WARN_IF_UNDOCUMENTED`, `WARN_NO_PARAMDOC` and
  `WARN_AS_ERROR=FAIL_ON_WARNINGS` make any undocumented file, function
  (static ones included), type, member or macro fail the stage; the same
  configuration produces the HTML of `make api-docs`. The fields of
  `CLAUDE.md` 6.5.3 are written as `@brief`, `@details`, `@param`,
  `@return` and `@par` sections.
- **Runtime:** Alpine 3.22.2 with `sqlite-libs` and `libmicrohttpd`
  (image 26.5 MB, 1.2 MiB RAM), user 10001, `/data` owned by it; only the
  `services` network; no password (embedded database).
- **Header styles:** `.clang-format`, `.clang-tidy` and `Doxyfile` are
  registered as `#`-comment files in `templates/headers/styles.psv`.

## Consequences

- The memory-safety risk of C is mitigated by bounded buffers, analysers and
  the absence of request-body parsing, and accepted as Medium for an
  internal read-only service (`services/digit-0/docs/THREAT_MODEL.md`).
- The nine other digit steps implement the same observable behaviour and
  pass `make contract-digit-<d>`; the internal split (pure handler, store,
  metrics, log) is recommended, not required.
- The default `mem_limit` of compiled services (64 MB) is kept although the
  service uses about 1.2 MiB, so that every compiled service shares one
  class (`CLAUDE.md` 6.2); P11.2 may lower it.
