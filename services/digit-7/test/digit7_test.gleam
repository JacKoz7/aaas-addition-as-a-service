//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          test/digit7_test.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Entry point of the unit tests (gleeunit) and the tests
////                  of the configuration in src/digit7.gleam.
//// Related Docs:    services/digit-7/README.md, ADR-0029
////
//// Test entry point and configuration tests of the digit-7 service.
////
//// `gleam test` runs `main`, which runs every public `*_test` function of
//// the modules under `test/`.

import digit7
import digit7/log
import envoy
import gleam/erlang/process
import gleam/option.{Some}
import gleam/string
import gleeunit

/// Run every test module.
///
/// Parameters: none. Returns: Nil; the runtime exits non-zero when a test
/// fails. Errors: none. Side Effects: runs the tests.
/// Complexity: O(tests). Thread Safety: called once. Owner: Arithmetic
/// Excellence Center (AEC). Since: digit-7 0.1.0. Example: `gleam test`.
pub fn main() -> Nil {
  gleeunit.main()
}

/// A logger whose lines go to a subject of the calling process.
///
/// Parameters: `lines` — the subject. Returns: the logger at debug level.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: the
/// lines are received by the subject's owner. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `capture(process.new_subject())`.
pub fn capture(lines: process.Subject(String)) -> log.Logger {
  log.Logger(
    service: "digit-7",
    threshold: log.Debug,
    sink: Some(fn(line) { process.send(lines, line) }),
  )
}

/// Integers are accepted with 1 to 9 ASCII digits inside the range only.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn parse_int_test() {
  assert digit7.parse_int("8080", 1, 65_535) == Ok(8080)
  assert digit7.parse_int("0", 0, 9) == Ok(0)
  assert digit7.parse_int("10", 0, 9) == Error(Nil)
  assert digit7.parse_int("", 0, 9) == Error(Nil)
  assert digit7.parse_int("-1", -5, 9) == Error(Nil)
  assert digit7.parse_int("+1", 0, 9) == Error(Nil)
  assert digit7.parse_int(" 1", 0, 9) == Error(Nil)
  assert digit7.parse_int("1234567890", 0, 9_999_999_999) == Error(Nil)
  assert digit7.parse_int("x", 0, 9) == Error(Nil)
}

/// Defaults apply when the variables are unset; invalid values are
/// rejected and logged.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn load_config_test() {
  let lines = process.new_subject()
  let logger = capture(lines)
  envoy.unset("AAAS_BOOTSTRAP")
  envoy.unset("AAAS_DIGIT")
  envoy.unset("AAAS_HTTP_PORT")
  envoy.unset("AAAS_DB_PATH")
  envoy.unset("AAAS_MIGRATIONS_DIR")
  assert digit7.load_config(logger)
    == Ok(digit7.Config(7, 8080, "/data/digit-7.db", "/app/migrations"))

  envoy.set("AAAS_DIGIT", "x")
  assert digit7.load_config(logger) == Error(Nil)
  let assert Ok(line) = process.receive(lines, 100)
  assert line_has(line, "AAAS_DIGIT must be 0..9")
  envoy.unset("AAAS_DIGIT")

  envoy.set("AAAS_HTTP_PORT", "0")
  assert digit7.load_config(logger) == Error(Nil)
  envoy.unset("AAAS_HTTP_PORT")

  envoy.set("AAAS_BOOTSTRAP", "platform")
  assert digit7.load_config(logger) == Error(Nil)
  let assert Ok(_) = process.receive(lines, 100)
  let assert Ok(line) = process.receive(lines, 100)
  assert line_has(line, "unsupported AAAS_BOOTSTRAP")
  envoy.unset("AAAS_BOOTSTRAP")
}

/// An empty variable counts as unset.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn env_or_test() {
  envoy.set("DIGIT7_TEST_EMPTY", "")
  assert digit7.env_or("DIGIT7_TEST_EMPTY", "fallback") == "fallback"
  envoy.set("DIGIT7_TEST_EMPTY", "set")
  assert digit7.env_or("DIGIT7_TEST_EMPTY", "fallback") == "set"
  envoy.unset("DIGIT7_TEST_EMPTY")
}

/// A missing migrations directory stops the start with status 1.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn run_fails_without_migrations_test() {
  let lines = process.new_subject()
  envoy.set("AAAS_DB_PATH", ":memory:")
  envoy.set("AAAS_MIGRATIONS_DIR", "/nonexistent")
  assert digit7.run(capture(lines)) == 1
  let assert Ok(line) = process.receive(lines, 100)
  assert line_has(line, "the database cannot be prepared")
  envoy.unset("AAAS_DB_PATH")
  envoy.unset("AAAS_MIGRATIONS_DIR")
}

/// A database holding another digit stops the start with status 1.
///
/// Owner: AEC. Since: digit-7 0.1.0.
pub fn run_fails_for_another_digit_test() {
  let lines = process.new_subject()
  envoy.set("AAAS_DB_PATH", ":memory:")
  envoy.set("AAAS_MIGRATIONS_DIR", "migrations")
  envoy.set("AAAS_DIGIT", "5")
  assert digit7.run(capture(lines)) == 1
  let assert Ok(_) = process.receive(lines, 100)
  let assert Ok(line) = process.receive(lines, 100)
  assert line_has(line, "the database does not hold the configured digit")
  envoy.unset("AAAS_DB_PATH")
  envoy.unset("AAAS_MIGRATIONS_DIR")
  envoy.unset("AAAS_DIGIT")
}

/// Whether a log line contains a text.
///
/// Parameters: `line` — the line; `text` — the text. Returns: True when
/// contained. Errors: none. Side Effects: none. Complexity: O(n).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `line_has("{\"msg\":\"x\"}", "x")`.
pub fn line_has(line: String, text: String) -> Bool {
  string.contains(line, text)
}
