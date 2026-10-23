//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          test/digit7/api_test.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Unit tests of the digit contract (src/digit7/api.gleam)
////                  and the database (src/digit7/store.gleam) against the
////                  real migrations in an in-memory SQLite database.
//// Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0029
////
//// Contract and database tests of the digit-7 service.

import digit7/api
import digit7/metrics
import digit7/store
import digit7_test
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/int
import gleam/option.{None, Some}
import gleam/string

/// A migrated in-memory store.
///
/// Parameters: none. Returns: the store with the seed of digit 7.
/// Errors: panics when the migrations fail (a test failure).
/// Side Effects: opens an in-memory database. Complexity: O(1).
/// Thread Safety: caller only. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-7 0.1.0. Example: `fresh_store()`.
pub fn fresh_store() -> store.Store {
  let logger = digit7_test.capture(process.new_subject())
  let assert Ok(opened) = store.open(":memory:", logger)
  let assert Ok(1) = store.migrate(opened, "migrations")
  opened
}

/// A contract state over a fresh store.
///
/// Parameters: `digit` — the configured digit. Returns: the state.
/// Errors: as `fresh_store`. Side Effects: as `fresh_store`.
/// Complexity: O(1). Thread Safety: caller only. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `state(7)`.
pub fn state(digit: Int) -> api.State {
  api.State(
    store: fresh_store(),
    digit:,
    metrics: metrics.new(digit, "0.1.0"),
    log: digit7_test.capture(process.new_subject()),
  )
}

/// GET /value answers the value read from the database.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn value_test() {
  let #(_, reply) = api.handle(state(7), "GET", "/value")
  assert reply
    == api.Reply(200, api.json_type, "{\"digit\":7,\"value\":7}", None)
}

/// GET /next answers the successor 8 without a carry.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn next_test() {
  let #(_, reply) = api.handle(state(7), "GET", "/next")
  assert reply
    == api.Reply(
      200,
      api.json_type,
      "{\"digit\":7,\"next\":8,\"carry\":false}",
      None,
    )
}

/// The values come from the database: a changed row changes the reply.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn value_comes_from_database_test() {
  let current = state(7)
  let assert Ok(Nil) =
    store.execute(current.store, "UPDATE digit SET next = 9, carry = 1;")
  let #(_, reply) = api.handle(current, "GET", "/next")
  assert reply.body == "{\"digit\":7,\"next\":9,\"carry\":true}"
}

/// GET /health is 200 with the database check.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn health_test() {
  let #(_, reply) = api.handle(state(7), "GET", "/health")
  assert reply.status == 200
  assert reply.body == "{\"status\":\"ok\",\"checks\":{\"database\":\"ok\"}}"
}

/// Requests are counted per endpoint and outcome and exposed in /metrics.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn metrics_count_test() {
  let #(current, _) = api.handle(state(7), "GET", "/value")
  let #(current, _) = api.handle(current, "GET", "/next")
  let #(current, _) = api.handle(current, "GET", "/next")
  let #(_, reply) = api.handle(current, "GET", "/metrics")
  assert reply.status == 200
  assert reply.content_type == api.prometheus_type
  assert string.contains(
    reply.body,
    "digit_requests_total{digit=\"7\",endpoint=\"value\",outcome=\"ok\"} 1\n",
  )
  assert string.contains(
    reply.body,
    "digit_requests_total{digit=\"7\",endpoint=\"next\",outcome=\"ok\"} 2\n",
  )
  assert string.contains(
    reply.body,
    "digit_requests_total{digit=\"7\",endpoint=\"next\",outcome=\"error\"} 0\n",
  )
  assert string.contains(
    reply.body,
    "digit_build_info{digit=\"7\",version=\"0.1.0\"} 1\n",
  )
}

/// Unknown paths are 404 problem details for every method.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn unknown_path_test() {
  let #(_, reply) = api.handle(state(7), "GET", "/nope")
  assert reply.status == 404
  assert reply.content_type == api.problem_type
  assert reply.body
    == "{\"type\":\"about:blank\",\"title\":\"Not Found\",\"status\":404,"
    <> "\"detail\":\"the digit service has no such path\"}"
  let #(_, reply) = api.handle(state(7), "DELETE", "/")
  assert reply.status == 404
}

/// Other methods than GET are 405 with Allow: GET, HEAD included.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn method_not_allowed_test() {
  let #(_, reply) = api.handle(state(7), "POST", "/next")
  assert reply.status == 405
  assert reply.allow == Some("GET")
  let #(_, reply) = api.handle(state(7), "HEAD", "/value")
  assert reply.status == 405
}

/// A database that holds another digit gives 503 and counts an error.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn another_digit_test() {
  let #(current, reply) = api.handle(state(6), "GET", "/value")
  assert reply.status == 503
  assert reply.content_type == api.problem_type
  assert metrics.get(current.metrics, metrics.Value, metrics.Failed) == 1
  let #(_, reply) = api.handle(current, "GET", "/health")
  assert reply.status == 503
  assert reply.body
    == "{\"status\":\"error\",\"checks\":{\"database\":\"error\"}}"
}

/// A missing table gives 503 and an error log line; restoring it heals.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn missing_table_test() {
  let lines = process.new_subject()
  let current = api.State(..state(7), log: digit7_test.capture(lines))
  let assert Ok(Nil) =
    store.execute(current.store, "ALTER TABLE digit RENAME TO hidden;")
  let #(_, reply) = api.handle(current, "GET", "/next")
  assert reply.status == 503
  let assert Ok(line) = process.receive(lines, 100)
  assert string.contains(line, "cannot read the digit from the database")
  assert string.contains(line, "no such table: digit")
  let assert Ok(Nil) =
    store.execute(current.store, "ALTER TABLE hidden RENAME TO digit;")
  let #(_, reply) = api.handle(current, "GET", "/next")
  assert reply.status == 200
}

/// Problem details escape their title and detail.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn problem_escape_test() {
  let reply = api.problem(400, "a\"b", "c\nd", None)
  assert reply.body
    == "{\"type\":\"about:blank\",\"title\":\"a\\\"b\",\"status\":400,"
    <> "\"detail\":\"c\\nd\"}"
}

/// The contract process answers through `answer`.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn contract_process_test() {
  let assert Ok(contract) = api.start(state(7))
  assert api.answer(contract, "GET", "/value").body
    == "{\"digit\":7,\"value\":7}"
  let metrics_reply = api.answer(contract, "GET", "/metrics")
  assert string.contains(
    metrics_reply.body,
    "endpoint=\"value\",outcome=\"ok\"} 1\n",
  )
}

/// Migrations are applied once; a second run applies none.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn migrate_once_test() {
  let opened = fresh_store()
  assert store.migrate(opened, "migrations") == Ok(0)
  assert store.is_applied(opened, "0001_digit.sql")
  assert store.read(opened) == Ok(store.DigitRow(7, 7, 8, False))
}

/// An empty table and a second row are both read errors.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn read_row_count_test() {
  let opened = fresh_store()
  let assert Ok(Nil) =
    store.execute(opened, "INSERT INTO digit VALUES (8, 8, 9, 0);")
  assert store.read(opened)
    == Error(store.StoreError("the table digit holds more than one row"))
  let assert Ok(Nil) = store.execute(opened, "DELETE FROM digit;")
  assert store.read(opened)
    == Error(store.StoreError("the table digit holds no row"))
}

/// The schema rejects values outside 0..9.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn schema_checks_test() {
  let opened = fresh_store()
  let assert Error(_) = store.execute(opened, "UPDATE digit SET next = 10;")
}

/// A failing migration is rolled back whole and named in the error.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn failed_migration_test() {
  let dir = "/tmp/digit7-test-" <> int.to_string(unique())
  let _ = make_dir(dir)
  let _ = write_file(dir <> "/0001_ok.sql", "CREATE TABLE a (x INTEGER);")
  let _ =
    write_file(
      dir <> "/0002_bad.sql",
      "CREATE TABLE b (x INTEGER); INSERT INTO missing VALUES (1);",
    )
  let _ = write_file(dir <> "/.hidden.sql", "garbage")
  let _ = write_file(dir <> "/notes.txt", "garbage")
  let logger = digit7_test.capture(process.new_subject())
  let assert Ok(opened) = store.open(":memory:", logger)
  assert store.list_migrations(dir) == Ok(["0001_ok.sql", "0002_bad.sql"])
  let assert Error(store.StoreError(message)) = store.migrate(opened, dir)
  assert string.starts_with(message, "migration 0002_bad.sql failed: ")
  assert store.is_applied(opened, "0001_ok.sql")
  assert !store.is_applied(opened, "0002_bad.sql")
  let assert Error(_) = store.execute(opened, "SELECT * FROM b;")
}

/// A missing migrations directory is an error.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn missing_dir_test() {
  assert store.list_migrations("/nonexistent")
    == Error(store.StoreError(
      "cannot read the migrations directory /nonexistent",
    ))
}

/// `erlang:unique_integer/1` with `positive`.
///
/// Parameters: `options` — `[positive]`. Returns: a unique integer.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `unique_integer([Positive])`.
@external(erlang, "erlang", "unique_integer")
fn unique_integer(options: List(UniqueOption)) -> Int

/// Options of `erlang:unique_integer/1`.
///
/// Owner: AEC. Since: digit-7 0.1.0.
type UniqueOption {
  /// The Erlang atom `positive`.
  Positive
}

/// A positive integer unique in this runtime.
///
/// Parameters: none. Returns: the integer. Errors: none. Side Effects:
/// none. Complexity: O(1). Thread Safety: safe. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `unique()`.
fn unique() -> Int {
  unique_integer([Positive])
}

/// `file:make_dir/1`.
///
/// Parameters: `dir` — the directory. Returns: `ok` or the error.
/// Errors: as the result says. Side Effects: creates the directory.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `make_dir("/tmp/x")`.
@external(erlang, "file", "make_dir")
fn make_dir(dir: String) -> Dynamic

/// `file:write_file/2`.
///
/// Parameters: `path` — the file; `data` — its content. Returns: `ok` or
/// the error. Errors: as the result says. Side Effects: writes the file.
/// Complexity: O(n). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `write_file("/tmp/x/a.sql", "SELECT 1;")`.
@external(erlang, "file", "write_file")
fn write_file(path: String, data: String) -> Dynamic
