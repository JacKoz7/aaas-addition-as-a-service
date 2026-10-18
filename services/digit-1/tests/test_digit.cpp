// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          tests/test_digit.cpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Unit tests of digit-1 (doctest): migrations, the
//                  database read, every reply of the HTTP contract, the
//                  proof that answers come from the database, metrics, trace
//                  parsing and the log line format.
// Related Docs:    services/digit-1/README.md, contracts/http/digit.yaml

/**
 * @file test_digit.cpp
 * @brief Unit tests (doctest 2.4).
 *
 * @details Each test case opens a fresh in-memory database migrated with
 * the real files of `migrations/`, so the tests exercise the same seed as
 * the service. Run from the service directory (the build stage `test`
 * does); the migrations directory can be overridden with
 * AAAS_MIGRATIONS_DIR.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#define DOCTEST_CONFIG_IMPLEMENT
#include <cstdlib>
#include <doctest/doctest.h>
#include <nlohmann/json.hpp>
#include <string>

#include "../src/api.hpp"
#include "../src/log.hpp"
#include "../src/metrics.hpp"
#include "../src/store.hpp"
#include "../src/trace.hpp"

namespace {

using namespace aaas::digit;

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
 * Safe while no thread modifies the environment.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * store.migrate(migrations_dir());
 * @endcode
 * @see Fixture
 */
std::string migrations_dir() {
  const char *dir = std::getenv("AAAS_MIGRATIONS_DIR"); // NOLINT(concurrency-mt-unsafe): tests are single-threaded
  return dir != nullptr ? dir : "migrations";
}

/**
 * @brief A migrated in-memory database with the service objects around it.
 *
 * @details Construction migrates with the real files; a failure throws and
 * fails the test case.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
struct Fixture {
  Store store{":memory:"};                       ///< In-memory database.
  int applied = store.migrate(migrations_dir()); ///< Files applied on construction.
  Metrics metrics{1, "test"};                    ///< Counters of the Api.
  Api api{store, 1, metrics};                    ///< The contract under test, digit 1.
};

/**
 * @brief Parse a reply body as JSON.
 *
 * @details Throws on invalid JSON, which fails the test case.
 *
 * @param reply Reply.
 * @return The parsed body.
 *
 * @par Errors
 * nlohmann::json::parse_error for invalid JSON.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the body length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * CHECK(body(reply)["next"] == 2);
 * @endcode
 * @see Api::handle
 */
nlohmann::json body(const Reply &reply) { return nlohmann::json::parse(reply.body); }

} // namespace

/// @brief Migrations create the seed once and are idempotent.
TEST_CASE("migrations create the seed once") {
  Fixture f;
  CHECK(f.applied == 1);
  CHECK(f.store.migrate(migrations_dir()) == 0);
  CHECK(f.store.read() == DigitRow{.digit = 1, .value = 1, .next = 2, .carry = false});
  CHECK_THROWS_AS(f.store.migrate("/nonexistent-directory"), StoreError);
}

/// @brief GET /value and GET /next answer the contract's bodies.
TEST_CASE("value and next answer the contract") {
  Fixture f;
  Reply reply = f.api.handle("GET", "/value");
  CHECK(reply.status == 200);
  CHECK(reply.content_type == "application/json");
  CHECK(reply.body == R"({"digit":1,"value":1})");
  reply = f.api.handle("GET", "/next");
  CHECK(reply.status == 200);
  CHECK(reply.body == R"({"digit":1,"next":2,"carry":false})");
  CHECK_FALSE(reply.allow.has_value());
}

/// @brief Answers follow the database, not the code (CLAUDE.md 4.4).
TEST_CASE("answers come from the database") {
  Fixture f;
  f.store.execute("UPDATE digit SET next = 7, carry = 1;");
  CHECK(f.api.handle("GET", "/next").body == R"({"digit":1,"next":7,"carry":true})");
}

/// @brief An unreadable or foreign row yields 503 and an unhealthy service.
TEST_CASE("database failures answer 503") {
  Fixture f;
  Reply reply = f.api.handle("GET", "/health");
  CHECK(reply.status == 200);
  CHECK(reply.body == R"({"status":"ok","checks":{"database":"ok"}})");

  Api foreign(f.store, 4, f.metrics); // the row names digit 1, this Api serves 4
  CHECK(foreign.handle("GET", "/value").status == 503);

  f.store.execute("DELETE FROM digit;");
  reply = f.api.handle("GET", "/next");
  CHECK(reply.status == 503);
  CHECK(reply.content_type == "application/problem+json");
  CHECK(body(reply)["status"] == 503);
  CHECK(body(reply)["type"] == "about:blank");
  reply = f.api.handle("GET", "/health");
  CHECK(reply.status == 503);
  CHECK(reply.body == R"({"status":"error","checks":{"database":"error"}})");
  CHECK(f.metrics.get(Endpoint::next, Outcome::error) == 1);
  CHECK(f.metrics.get(Endpoint::value, Outcome::error) == 1);
  CHECK_THROWS_AS((void)f.store.read(), StoreError);
}

/// @brief Two rows are an error, not a silent choice of one.
TEST_CASE("more than one row is an error") {
  Fixture f;
  f.store.execute("INSERT INTO digit (digit, value, next, carry) VALUES (2, 2, 3, 0);");
  CHECK_THROWS_AS((void)f.store.read(), StoreError);
  CHECK(f.api.handle("GET", "/value").status == 503);
}

/// @brief Unknown paths answer 404, other methods 405 with Allow: GET.
TEST_CASE("unknown paths and methods") {
  Fixture f;
  Reply reply = f.api.handle("GET", "/nope");
  CHECK(reply.status == 404);
  CHECK(reply.content_type == "application/problem+json");
  CHECK(body(reply)["status"] == 404);
  reply = f.api.handle("POST", "/value");
  CHECK(reply.status == 405);
  CHECK(reply.allow == "GET");
  CHECK(f.api.handle("DELETE", "/nope").status == 404);
}

/// @brief The counter counts value and next by outcome; the text is valid.
TEST_CASE("metrics") {
  Fixture f;
  (void)f.api.handle("GET", "/next");
  (void)f.api.handle("GET", "/next");
  (void)f.api.handle("GET", "/value");
  const Reply reply = f.api.handle("GET", "/metrics");
  CHECK(reply.status == 200);
  CHECK(reply.content_type.starts_with("text/plain"));
  CHECK(reply.body.find("# TYPE digit_requests_total counter\n") != std::string::npos);
  CHECK(reply.body.find("digit_requests_total{digit=\"1\",endpoint=\"next\",outcome=\"ok\"} 2\n") != std::string::npos);
  CHECK(reply.body.find("digit_requests_total{digit=\"1\",endpoint=\"value\",outcome=\"ok\"} 1\n") !=
        std::string::npos);
  CHECK(reply.body.find("digit_requests_total{digit=\"1\",endpoint=\"value\",outcome=\"error\"} 0\n") !=
        std::string::npos);
  CHECK(reply.body.find("digit_build_info{digit=\"1\",version=\"test\"} 1\n") != std::string::npos);
}

/// @brief traceparent: valid headers are parsed, invalid ones rejected.
TEST_CASE("traceparent parsing") {
  const auto parsed = parse_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
  REQUIRE(parsed.has_value());
  const TraceContext ctx = parsed.value_or(TraceContext{});
  CHECK(ctx.trace_id == "4bf92f3577b34da6a3ce929d0e0e4736");
  CHECK(ctx.span_id == "00f067aa0ba902b7");
  CHECK_FALSE(parse_traceparent(""));
  CHECK_FALSE(parse_traceparent("00-00000000000000000000000000000000-00f067aa0ba902b7-01"));
  CHECK_FALSE(parse_traceparent("00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01"));
  CHECK_FALSE(parse_traceparent("ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"));
  CHECK_FALSE(parse_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7"));
}

/// @brief Log lines carry the fields of CLAUDE.md 6.1; levels parse.
TEST_CASE("log line format and levels") {
  logging::init("digit-1-test", logging::Level::off);
  const auto line = nlohmann::json::parse(
      logging::render(logging::Level::warn, "a \"quoted\"\nmessage",
                      parse_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"), "detail"));
  CHECK(line["level"] == "warn");
  CHECK(line["service"] == "digit-1-test");
  CHECK(line["msg"] == "a \"quoted\"\nmessage");
  CHECK(line["taskId"].is_null());
  CHECK(line["traceId"] == "4bf92f3577b34da6a3ce929d0e0e4736");
  CHECK(line["spanId"] == "00f067aa0ba902b7");
  CHECK(line["detail"] == "detail");
  CHECK(line["ts"].get<std::string>().ends_with("Z"));
  const auto bare = nlohmann::json::parse(logging::render(logging::Level::info, "x", std::nullopt, std::nullopt));
  CHECK(bare["traceId"].is_null());
  CHECK_FALSE(bare.contains("detail"));
  CHECK(logging::parse_level("debug", logging::Level::info) == logging::Level::debug);
  CHECK(logging::parse_level("error", logging::Level::info) == logging::Level::error);
  CHECK(logging::parse_level("verbose", logging::Level::warn) == logging::Level::warn);
  CHECK(logging::parse_level(std::nullopt, logging::Level::info) == logging::Level::info);
}

/**
 * @brief Run every test case with logs suppressed.
 *
 * @details The failure tests provoke error lines on purpose, so the
 * threshold is set above error before doctest runs.
 *
 * @param argc Argument count (doctest options).
 * @param argv Arguments (doctest options).
 * @return 0 when every check passed, non-zero otherwise.
 *
 * @par Errors
 * Non-zero exit status on failed checks.
 * @par Side Effects
 * Writes the doctest report to stdout.
 * @par Complexity
 * Not applicable.
 * @par Thread Safety
 * Not applicable (process entry point).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * ./test_digit --success=false
 * @endcode
 * @see Fixture
 */
int main(int argc, char **argv) {
  logging::init("digit-1-test", logging::Level::off);
  doctest::Context context(argc, argv);
  return context.run();
}
