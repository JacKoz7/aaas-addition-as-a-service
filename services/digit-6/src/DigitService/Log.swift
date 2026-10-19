// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          src/DigitService/Log.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Structured JSON log lines on stdout with the fields of
//                  CLAUDE.md 6.1, and the JSON string escaping shared with
//                  the response bodies.
// Related Docs:    CLAUDE.md 6.1, services/digit-6/README.md, ADR-0022

#if canImport(Glibc)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#endif

/// Severity of a log line, in increasing order.
///
/// Business Justification: `AAAS_LOG_LEVEL` selects the verbosity without
/// a rebuild.
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public enum Level: Int, Comparable, Sendable, CaseIterable {
  /// One line per request.
  case debug
  /// Start-up, migrations, shutdown.
  case info
  /// Conditions that need attention but do not fail requests.
  case warn
  /// Failures.
  case error

  /// The name written in the `level` field.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `Level.warn.name == "warn"`.
  public var name: String {
    switch self {
    case .debug: return "debug"
    case .info: return "info"
    case .warn: return "warn"
    case .error: return "error"
    }
  }

  /// Parse a level name.
  ///
  /// Description: accepts debug, info, warn and error (lower case).
  ///
  /// Business Justification: the value of `AAAS_LOG_LEVEL`.
  ///
  /// - Parameters:
  ///   - name: Level name, nil when unset.
  ///   - fallback: Level used when `name` is nil or unknown.
  /// - Returns: The level.
  ///
  /// Errors: none (the fallback for unknown names). Side Effects: none.
  /// Complexity: O(1). Thread Safety: safe. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `Level.parse("debug", fallback: .info) == .debug`.
  ///
  /// See Also: ``Logger``.
  public static func parse(_ name: String?, fallback: Level) -> Level {
    allCases.first { $0.name == name } ?? fallback
  }

  /// Order levels by severity.
  ///
  /// - Parameters:
  ///   - lhs: A level.
  ///   - rhs: Another level.
  /// - Returns: True when `lhs` is less severe than `rhs`.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `Level.debug < Level.info`.
  public static func < (lhs: Level, rhs: Level) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Escape a string for use inside a JSON string literal.
///
/// Description: escapes the quote, the backslash, newline, carriage return
/// and tab with their short forms, and every other control character below
/// U+0020 as `\u00XX`. Other characters are kept.
///
/// Business Justification: log lines and problem details must stay valid
/// JSON whatever a request path or an SQLite message contains.
///
/// - Parameter text: Any string.
/// - Returns: The escaped text, without surrounding quotes.
///
/// Errors: none. Side Effects: none. Complexity: O(n) time and memory.
/// Thread Safety: safe (pure). Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-6 0.1.0.
///
/// Example: `jsonEscape("a\"b") == "a\\\"b"`.
///
/// See Also: ``Logger/write(_:_:traceId:spanId:detail:)``.
public func jsonEscape(_ text: String) -> String {
  var out = ""
  out.reserveCapacity(text.utf8.count)
  for scalar in text.unicodeScalars {
    switch scalar {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\n": out += "\\n"
    case "\r": out += "\\r"
    case "\t": out += "\\t"
    case _ where scalar.value < 0x20:
      let hex = String(scalar.value, radix: 16)
      out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
    default: out.unicodeScalars.append(scalar)
    }
  }
  return out
}

/// A JSON string literal, or `null` for nil.
///
/// Business Justification: absent ids are written as null, not as "".
///
/// - Parameter value: Text or nil.
/// - Returns: A JSON value.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
/// Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `quoted(nil) == "null"`.
///
/// See Also: ``jsonEscape(_:)``.
private func quoted(_ value: String?) -> String {
  value.map { "\"" + jsonEscape($0) + "\"" } ?? "null"
}

/// Current UTC time as ISO 8601 with milliseconds.
///
/// Business Justification: the `ts` field of every line (CLAUDE.md 6.1).
///
/// - Returns: For example `2026-10-19T12:00:00.000Z`.
///
/// Errors: none. Side Effects: reads the clock. Complexity: O(1).
/// Thread Safety: safe (`gmtime_r`). Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `let ts = timestamp()`.
func timestamp() -> String {
  var now = timespec()
  clock_gettime(CLOCK_REALTIME, &now)
  var seconds = now.tv_sec
  var parts = tm()
  gmtime_r(&seconds, &parts)
  var buffer = [CChar](repeating: 0, count: 32)
  let length = strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S", &parts)
  let base = String(
    decoding: buffer[0..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
  let millis = Int(now.tv_nsec / 1_000_000)
  return base + "." + String(repeating: "0", count: millis < 10 ? 2 : millis < 100 ? 1 : 0)
    + String(millis) + "Z"
}

/// Writer of JSON log lines for one service.
///
/// Description: every line is one JSON object with `ts`, `level`,
/// `service`, `msg`, `taskId`, `traceId`, `spanId` and an optional
/// `detail` (CLAUDE.md 6.1). `taskId` is always null: a digit request does
/// not carry a task.
///
/// Business Justification: structured logs are collected by the
/// observability stack (CLAUDE.md 6.1, P7.1).
///
/// Thread Safety: safe; immutable, and a line is written with one call.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public final class Logger: Sendable {
  /// Service name written in every line.
  public let service: String
  /// Minimum level written.
  public let threshold: Level
  /// Receives each line instead of stdout when set (used by the tests).
  private let sink: (@Sendable (String) -> Void)?

  /// Create a logger.
  ///
  /// - Parameters:
  ///   - service: Service name, for example digit-6.
  ///   - threshold: Lines below this level are not written.
  ///   - sink: Receives each line instead of stdout; nil for stdout.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let log = Logger(service: "digit-6", threshold: .info)`.
  ///
  /// See Also: ``write(_:_:traceId:spanId:detail:)``.
  public init(
    service: String, threshold: Level, sink: (@Sendable (String) -> Void)? = nil
  ) {
    self.service = service
    self.threshold = threshold
    self.sink = sink
  }

  /// Write one JSON log line.
  ///
  /// Description: nothing is written when `level` is below the threshold.
  /// The detail field is present only when `detail` is not nil. Each line
  /// is written to stdout with a single unbuffered write.
  ///
  /// Business Justification: structured logs (CLAUDE.md 6.1).
  ///
  /// - Parameters:
  ///   - level: Severity of the line.
  ///   - msg: Message, constant per call site.
  ///   - traceId: Trace id of the request, nil when none.
  ///   - spanId: Caller's span id, nil when none.
  ///   - detail: Variable part, nil when none.
  ///
  /// Errors: none. Side Effects: writes to stdout (descriptor 1) or the sink.
  /// Complexity: O(n) in the length of the line. Thread Safety: safe.
  /// Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `log.write(.info, "listening", detail: "port 8080")`.
  ///
  /// See Also: ``jsonEscape(_:)``.
  public func write(
    _ level: Level, _ msg: String, traceId: String? = nil, spanId: String? = nil,
    detail: String? = nil
  ) {
    guard level >= threshold else { return }
    var line =
      "{\"ts\":\"\(timestamp())\",\"level\":\"\(level.name)\",\"service\":\(quoted(service)),"
      + "\"msg\":\(quoted(msg)),\"taskId\":null,\"traceId\":\(quoted(traceId)),"
      + "\"spanId\":\(quoted(spanId))"
    if let detail {
      line += ",\"detail\":\(quoted(detail))"
    }
    line += "}"
    if let sink {
      sink(line)
    } else {
      // One write(2) per line on descriptor 1: lines from concurrent
      // connection threads never interleave, and nothing is buffered.
      let bytes = Array((line + "\n").utf8)
      _ = bytes.withUnsafeBytes { Glibc.write(1, $0.baseAddress, $0.count) }
    }
  }
}
