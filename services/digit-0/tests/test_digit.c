/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          tests/test_digit.c
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Unit tests of digit-0: migrations, the database read,
 *                  every reply of the HTTP contract, the proof that answers
 *                  come from the database, metrics, trace parsing and JSON
 *                  escaping.
 * Related Docs:    services/digit-0/README.md, contracts/http/digit.yaml
 */

/**
 * @file test_digit.c
 * @brief Unit tests (no framework: a check macro and a runner).
 *
 * @details Each test opens a fresh in-memory database migrated with the
 * real files of `migrations/`, so the tests exercise the same seed as the
 * service. Run from the service directory (the build stage `test` does);
 * the migrations directory can be overridden with AAAS_MIGRATIONS_DIR.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../src/api.h"
#include "../src/log.h"
#include "../src/metrics.h"
#include "../src/store.h"
#include "../src/trace.h"

/** @brief Number of failed checks in the whole run. */
static int failures;

/** @brief Number of executed checks in the whole run. */
static int checks;

/**
 * @brief Record one check; print the failing expression with its location.
 *
 * @param cond Expression that must be true.
 */
#define CHECK(cond)                                                                                                    \
  do {                                                                                                                 \
    checks++;                                                                                                          \
    if (!(cond)) {                                                                                                     \
      failures++;                                                                                                      \
      (void)fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);                                            \
    }                                                                                                                  \
  } while (0)

/**
 * @brief A migrated in-memory database with the service context around it.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
struct fixture {
  sqlite3 *db;            /**< In-memory database migrated with migrations/. */
  struct metrics metrics; /**< Counters of the context. */
  struct api_context ctx; /**< Context passed to api_handle. */
};

/**
 * @brief Directory of the migration files used by the tests.
 *
 * @details AAAS_MIGRATIONS_DIR, or `migrations` relative to the working
 * directory.
 *
 * @return The directory.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Reads the environment.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * store_migrate(db, migrations_dir(), NULL);
 * @endcode
 * @see setup
 */
static const char *migrations_dir(void) {
  const char *dir = getenv("AAAS_MIGRATIONS_DIR");
  return dir != NULL ? dir : "migrations";
}

/**
 * @brief Create a fresh fixture for digit 0.
 *
 * @details Aborts the run when the database cannot be prepared, because
 * every later check would be meaningless.
 *
 * @param[out] f Fixture to initialise.
 *
 * @par Errors
 * Exits with status 2 when the database cannot be opened or migrated.
 * @par Side Effects
 * Allocates an in-memory database.
 * @par Complexity
 * O(s) in the size of the migrations.
 * @par Thread Safety
 * Not applicable (tests run sequentially).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * struct fixture f;
 * setup(&f);
 * @endcode
 * @see teardown
 */
static void setup(struct fixture *f) {
  if (store_open(":memory:", &f->db) != 0 || store_migrate(f->db, migrations_dir(), NULL) != 0) {
    (void)fprintf(stderr, "cannot prepare the test database\n");
    exit(2);
  }
  metrics_init(&f->metrics, 0, "test");
  f->ctx = (struct api_context){.db = f->db, .digit = 0, .metrics = &f->metrics};
}

/**
 * @brief Release a fixture.
 *
 * @param f Fixture from setup().
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Closes the database.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not applicable.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * teardown(&f);
 * @endcode
 * @see setup
 */
static void teardown(struct fixture *f) { store_close(f->db); }

/**
 * @brief Migrations create the seed once and are idempotent.
 *
 * @details A second run applies no file; the row is digit 0 → 1, no carry.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_migrations(void) {
  struct fixture f;
  setup(&f);
  int applied = -1;
  CHECK(store_migrate(f.db, migrations_dir(), &applied) == 0);
  CHECK(applied == 0);
  struct digit_row row;
  CHECK(store_read(f.db, &row) == 0);
  CHECK(row.digit == 0 && row.value == 0 && row.next == 1 && !row.carry);
  CHECK(store_migrate(f.db, "/nonexistent-directory", NULL) == -1);
  teardown(&f);
}

/**
 * @brief GET /value and GET /next answer the contract's bodies.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_value_and_next(void) {
  struct fixture f;
  setup(&f);
  struct api_reply reply;
  api_handle(&f.ctx, "GET", "/value", &reply);
  CHECK(reply.status == 200);
  CHECK(strcmp(reply.content_type, "application/json") == 0);
  CHECK(strcmp(reply.body, "{\"digit\":0,\"value\":0}") == 0);
  api_handle(&f.ctx, "GET", "/next", &reply);
  CHECK(reply.status == 200);
  CHECK(strcmp(reply.body, "{\"digit\":0,\"next\":1,\"carry\":false}") == 0);
  CHECK(reply.allow == NULL);
  teardown(&f);
}

/**
 * @brief Answers follow the database, not the code (CLAUDE.md 4.4).
 *
 * @details Changing the row changes the answer of the next request.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_answers_come_from_the_database(void) {
  struct fixture f;
  setup(&f);
  CHECK(sqlite3_exec(f.db, "UPDATE digit SET next = 7, carry = 1;", NULL, NULL, NULL) == SQLITE_OK);
  struct api_reply reply;
  api_handle(&f.ctx, "GET", "/next", &reply);
  CHECK(strcmp(reply.body, "{\"digit\":0,\"next\":7,\"carry\":true}") == 0);
  teardown(&f);
}

/**
 * @brief An unreadable or foreign row yields 503 and an unhealthy service.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_database_failures(void) {
  struct fixture f;
  setup(&f);
  struct api_reply reply;
  api_handle(&f.ctx, "GET", "/health", &reply);
  CHECK(reply.status == 200);
  CHECK(strcmp(reply.body, "{\"status\":\"ok\",\"checks\":{\"database\":\"ok\"}}") == 0);

  f.ctx.digit = 4; /* the row names digit 0, the service is configured for 4 */
  api_handle(&f.ctx, "GET", "/value", &reply);
  CHECK(reply.status == 503);
  f.ctx.digit = 0;

  CHECK(sqlite3_exec(f.db, "DELETE FROM digit;", NULL, NULL, NULL) == SQLITE_OK);
  api_handle(&f.ctx, "GET", "/next", &reply);
  CHECK(reply.status == 503);
  CHECK(strcmp(reply.content_type, "application/problem+json") == 0);
  CHECK(strstr(reply.body, "\"status\":503") != NULL);
  api_handle(&f.ctx, "GET", "/health", &reply);
  CHECK(reply.status == 503);
  CHECK(strcmp(reply.body, "{\"status\":\"error\",\"checks\":{\"database\":\"error\"}}") == 0);
  CHECK(f.metrics.requests[ENDPOINT_NEXT][OUTCOME_ERROR] == 1);
  CHECK(f.metrics.requests[ENDPOINT_VALUE][OUTCOME_ERROR] == 1);
  teardown(&f);
}

/**
 * @brief Unknown paths answer 404, other methods 405 with Allow: GET.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_errors(void) {
  struct fixture f;
  setup(&f);
  struct api_reply reply;
  api_handle(&f.ctx, "GET", "/nope", &reply);
  CHECK(reply.status == 404);
  CHECK(strcmp(reply.content_type, "application/problem+json") == 0);
  CHECK(strstr(reply.body, "\"status\":404") != NULL);
  api_handle(&f.ctx, "POST", "/value", &reply);
  CHECK(reply.status == 405);
  CHECK(reply.allow != NULL && strcmp(reply.allow, "GET") == 0);
  api_handle(&f.ctx, "DELETE", "/nope", &reply);
  CHECK(reply.status == 404);
  teardown(&f);
}

/**
 * @brief The counter counts value and next by outcome; the text is valid.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_metrics(void) {
  struct fixture f;
  setup(&f);
  struct api_reply reply;
  api_handle(&f.ctx, "GET", "/next", &reply);
  api_handle(&f.ctx, "GET", "/next", &reply);
  api_handle(&f.ctx, "GET", "/value", &reply);
  api_handle(&f.ctx, "GET", "/metrics", &reply);
  CHECK(reply.status == 200);
  CHECK(strncmp(reply.content_type, "text/plain", 10) == 0);
  CHECK(strstr(reply.body, "# TYPE digit_requests_total counter\n") != NULL);
  CHECK(strstr(reply.body, "digit_requests_total{digit=\"0\",endpoint=\"next\",outcome=\"ok\"} 2\n") != NULL);
  CHECK(strstr(reply.body, "digit_requests_total{digit=\"0\",endpoint=\"value\",outcome=\"ok\"} 1\n") != NULL);
  CHECK(strstr(reply.body, "digit_build_info{digit=\"0\",version=\"test\"} 1\n") != NULL);
  char tiny[16];
  CHECK(metrics_render(&f.metrics, tiny, sizeof tiny) == -1);
  teardown(&f);
}

/**
 * @brief traceparent: valid headers are parsed, invalid ones rejected.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_trace(void) {
  struct trace_context t;
  CHECK(trace_parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", &t));
  CHECK(strcmp(t.trace_id, "4bf92f3577b34da6a3ce929d0e0e4736") == 0);
  CHECK(strcmp(t.span_id, "00f067aa0ba902b7") == 0);
  CHECK(!trace_parse(NULL, &t));
  CHECK(!trace_parse("00-00000000000000000000000000000000-00f067aa0ba902b7-01", &t));
  CHECK(!trace_parse("00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01", &t));
  CHECK(!trace_parse("ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", &t));
  CHECK(!trace_parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7", &t));
}

/**
 * @brief JSON escaping and log level parsing.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
static void test_log_helpers(void) {
  char out[32];
  CHECK(json_escape(out, sizeof out, "a\"b\\c\nd\x01") == 16);
  CHECK(strcmp(out, "a\\\"b\\\\c\\nd\\u0001") == 0);
  char small[4];
  json_escape(small, sizeof small, "abcdef");
  CHECK(strcmp(small, "abc") == 0);
  CHECK(log_level_parse("debug", LVL_INFO) == LVL_DEBUG);
  CHECK(log_level_parse("error", LVL_INFO) == LVL_ERROR);
  CHECK(log_level_parse("verbose", LVL_WARN) == LVL_WARN);
  CHECK(log_level_parse(NULL, LVL_INFO) == LVL_INFO);
}

/**
 * @brief Run every test and report.
 *
 * @details Logs are suppressed (threshold above error): the failure tests
 * provoke error lines on purpose.
 *
 * @return 0 when every check passed, 1 otherwise.
 *
 * @par Errors
 * 2 when a fixture cannot be prepared (see setup()).
 * @par Side Effects
 * Writes the report to stdout and failures to stderr.
 * @par Complexity
 * Not applicable.
 * @par Thread Safety
 * Not applicable (process entry point).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * ./test_digit
 * @endcode
 * @see setup
 */
int main(void) {
  log_init("digit-0-test", LVL_OFF);
  test_migrations();
  test_value_and_next();
  test_answers_come_from_the_database();
  test_database_failures();
  test_errors();
  test_metrics();
  test_trace();
  test_log_helpers();
  printf("%d checks, %d failed\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
