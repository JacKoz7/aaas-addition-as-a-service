//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/log.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Structured JSON log lines on stdout with the fields of
////                  CLAUDE.md 6.1 (ts, level, service, msg, taskId,
////                  traceId, spanId).
//// Related Docs:    services/digit-7/README.md, CLAUDE.md 6.1, ADR-0029
////
//// Structured logging of the digit-7 service.
////
//// Every line is one JSON object written with a single `io:put_chars`
//// request, so lines of concurrent connection processes never interleave.
//// The digit service has no task, so `taskId` is always `null`.

import gleam/erlang/charlist.{type Charlist}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Severity of a log line, from the most verbose to the most severe.
///
/// Business Justification: operators filter the log stream by level
/// (`AAAS_LOG_LEVEL`); request lines are written at `Debug` only.
/// Thread Safety: an immutable value. Owner: Arithmetic Excellence Center
/// (AEC). Since: digit-7 0.1.0.
pub type Level {
  /// Per-request detail (`request answered`, `request rejected`).
  Debug
  /// Lifecycle events: migrations, listening, shutting down, stopped.
  Info
  /// Degraded but serving: connection limit reached, accept failed.
  Warn
  /// A failure: the database cannot be read, a start-up check failed.
  Error
}

/// A logger bound to one service name and a threshold.
///
/// Description: `sink` replaces stdout when set (the tests capture lines
/// with it); lines below `threshold` are dropped.
/// Thread Safety: an immutable value; `write` may be called from any
/// process. Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
pub type Logger {
  /// Create a logger.
  Logger(service: String, threshold: Level, sink: Option(fn(String) -> Nil))
}

/// Rank of a level, used to compare it with the threshold.
///
/// Parameters: `level` — any level. Returns: 0 (`Debug`) to 3 (`Error`).
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `rank(Warn) == 2`.
fn rank(level: Level) -> Int {
  case level {
    Debug -> 0
    Info -> 1
    Warn -> 2
    Error -> 3
  }
}

/// The name of a level as written in the `level` field.
///
/// Parameters: `level` — any level. Returns: `debug`, `info`, `warn` or
/// `error`. Errors: none. Side Effects: none. Complexity: O(1).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `level_name(Info) == "info"`.
pub fn level_name(level: Level) -> String {
  case level {
    Debug -> "debug"
    Info -> "info"
    Warn -> "warn"
    Error -> "error"
  }
}

/// Parse a level name, falling back for an unknown or empty name.
///
/// Business Justification: a mistyped `AAAS_LOG_LEVEL` must not stop the
/// service; it logs at the fallback level instead.
/// Parameters: `name` — the configured name; `fallback` — the level used
/// when `name` is not one of the four names. Returns: the level.
/// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `parse_level("warn", Info) == Warn`.
pub fn parse_level(name: String, fallback: Level) -> Level {
  [Debug, Info, Warn, Error]
  |> list.find(fn(level) { level_name(level) == name })
  |> option.from_result
  |> option.unwrap(fallback)
}

/// Escape a string for a JSON string literal (RFC 8259).
///
/// Description: escapes `"` and `\`, writes `\n`, `\r` and `\t` in short
/// form and every other control character below U+0020 as `\u00XX`.
/// Business Justification: a log or problem detail that quotes a value
/// must stay valid JSON whatever the value holds.
/// Parameters: `text` — any string. Returns: the escaped text, without
/// the surrounding quotes. Errors: none. Side Effects: none.
/// Complexity: O(n) time and memory. Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `json_escape("a\"b") == "a\\\"b"`.
pub fn json_escape(text: String) -> String {
  text
  |> string.to_utf_codepoints
  |> list.map(escape_codepoint)
  |> string.concat
}

/// Escape one code point for a JSON string literal.
///
/// Parameters: `codepoint` — one Unicode scalar value. Returns: its JSON
/// form. Errors: none. Side Effects: none. Complexity: O(1).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `escape_codepoint(tab) == "\\t"`.
fn escape_codepoint(codepoint: UtfCodepoint) -> String {
  case string.utf_codepoint_to_int(codepoint) {
    0x22 -> "\\\""
    0x5C -> "\\\\"
    0x0A -> "\\n"
    0x0D -> "\\r"
    0x09 -> "\\t"
    value if value < 0x20 ->
      "\\u" <> string.pad_start(int_to_hex(value), to: 4, with: "0")
    _ -> string.from_utf_codepoints([codepoint])
  }
}

/// Lower-case hexadecimal form of a non-negative integer.
///
/// Parameters: `value` — 0 or more. Returns: e.g. `1f`. Errors: none.
/// Side Effects: none. Complexity: O(log n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `int_to_hex(31) == "1f"`.
fn int_to_hex(value: Int) -> String {
  string.lowercase(integer_to_binary(value, 16))
}

/// `erlang:integer_to_binary/2`: an integer in the given base.
///
/// Parameters: `value` — the integer; `base` — 2..36. Returns: upper-case
/// digits. Errors: none for these arguments. Side Effects: none.
/// Complexity: O(log n). Thread Safety: pure. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `integer_to_binary(255, 16) == "FF"`.
@external(erlang, "erlang", "integer_to_binary")
fn integer_to_binary(value: Int, base: Int) -> String

/// A JSON string literal, or `null` for `None`.
///
/// Parameters: `value` — the optional text. Returns: `"…"` or `null`.
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `quoted(None) == "null"`.
fn quoted(value: Option(String)) -> String {
  case value {
    Some(text) -> "\"" <> json_escape(text) <> "\""
    None -> "null"
  }
}

/// Time units of `os:system_time/1` and `calendar:system_time_to_rfc3339/2`.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
type TimeUnit {
  /// The Erlang atom `millisecond`.
  Millisecond
}

/// Options of `calendar:system_time_to_rfc3339/2`.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
type Rfc3339Option {
  /// `{unit, Unit}`: the unit of the time passed in.
  Unit(TimeUnit)
  /// `{offset, Offset}`: the UTC offset written; `"Z"` for UTC.
  Offset(Charlist)
}

/// `os:system_time/1`: the system time in the given unit.
///
/// Parameters: `unit` — the unit. Returns: time since the Unix epoch.
/// Errors: none. Side Effects: reads the clock. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `system_time(Millisecond)`.
@external(erlang, "os", "system_time")
fn system_time(unit: TimeUnit) -> Int

/// `calendar:system_time_to_rfc3339/2`: format a system time.
///
/// Parameters: `time` — time since the epoch; `options` — unit and offset.
/// Returns: the RFC 3339 text as a charlist. Errors: none for valid
/// options. Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `to_rfc3339(0, [Unit(Millisecond), Offset(z)])`.
@external(erlang, "calendar", "system_time_to_rfc3339")
fn to_rfc3339(time: Int, options: List(Rfc3339Option)) -> Charlist

/// The current UTC time in RFC 3339 with milliseconds.
///
/// Business Justification: the `ts` field must be comparable across the
/// 35 services; every service writes UTC with a `Z` suffix.
/// Parameters: none. Returns: e.g. `2026-10-22T19:52:01.123Z`.
/// Errors: none. Side Effects: reads the clock. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `timestamp()`.
pub fn timestamp() -> String {
  system_time(Millisecond)
  |> to_rfc3339([Unit(Millisecond), Offset(charlist.from_string("Z"))])
  |> charlist.to_string
}

/// Format one log line without writing it.
///
/// Description: the fields are `ts`, `level`, `service`, `msg`, `taskId`
/// (always `null`), `traceId`, `spanId` and, when given, `detail`.
/// Parameters: `logger` — supplies the service name; `level`, `msg`,
/// `trace_id`, `span_id`, `detail` — the field values. Returns: the JSON
/// object, without a newline. Errors: none. Side Effects: reads the clock.
/// Complexity: O(n) in the length of the fields. Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `format(logger, Info, "stopped", None, None, None)`.
pub fn format(
  logger: Logger,
  level: Level,
  msg: String,
  trace_id: Option(String),
  span_id: Option(String),
  detail: Option(String),
) -> String {
  let base =
    "{\"ts\":\""
    <> timestamp()
    <> "\",\"level\":\""
    <> level_name(level)
    <> "\",\"service\":"
    <> quoted(Some(logger.service))
    <> ",\"msg\":"
    <> quoted(Some(msg))
    <> ",\"taskId\":null,\"traceId\":"
    <> quoted(trace_id)
    <> ",\"spanId\":"
    <> quoted(span_id)
  case detail {
    Some(_) -> base <> ",\"detail\":" <> quoted(detail) <> "}"
    None -> base <> "}"
  }
}

/// Write one log line if its level reaches the threshold.
///
/// Description: the line goes to the sink when one is set, otherwise to
/// stdout followed by a newline, in one `io:put_chars` request.
/// Parameters: `logger` — the logger; `level` — severity; `msg` — fixed
/// message; `trace_id`, `span_id` — the caller's W3C trace context, if
/// any; `detail` — variable detail, if any. Returns: Nil. Errors: none.
/// Side Effects: writes to stdout or calls the sink.
/// Complexity: O(n) in the length of the fields. Thread Safety: safe from
/// any process. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `write(logger, Info, "listening", None, None, Some("port 8080"))`.
/// See Also: `format`.
pub fn write(
  logger: Logger,
  level: Level,
  msg: String,
  trace_id: Option(String),
  span_id: Option(String),
  detail: Option(String),
) -> Nil {
  case rank(level) >= rank(logger.threshold) {
    False -> Nil
    True -> {
      let line = format(logger, level, msg, trace_id, span_id, detail)
      case logger.sink {
        Some(sink) -> sink(line)
        None -> io.println(line)
      }
    }
  }
}

/// Write a line without trace context.
///
/// Parameters: `logger`, `level`, `msg` — as in `write`; `detail` — the
/// detail, if any. Returns: Nil. Errors: none. Side Effects: as `write`.
/// Complexity: O(n). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `event(logger, Info, "stopped", None)`.
/// See Also: `write`.
pub fn event(
  logger: Logger,
  level: Level,
  msg: String,
  detail: Option(String),
) -> Nil {
  write(logger, level, msg, None, None, detail)
}
