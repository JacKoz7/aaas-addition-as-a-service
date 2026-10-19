// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          lib/src/log.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Structured JSON log lines on stdout with the fields of
//                  CLAUDE.md 6.1, and the JSON string escaping shared with
//                  the response bodies.
// Related Docs:    CLAUDE.md 6.1, services/digit-5/README.md, ADR-0022

/// Structured JSON logging of the digit service.
///
/// Every line is one JSON object with `ts`, `level`, `service`, `msg`,
/// `taskId`, `traceId`, `spanId` and an optional `detail` (CLAUDE.md 6.1).
/// `taskId` is always null: a digit request does not carry a task.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

import 'dart:convert';
import 'dart:io';

/// Severity of a log line, in increasing order.
///
/// Business Justification: AAAS_LOG_LEVEL selects the verbosity without a
/// rebuild.
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
enum Level {
  /// One line per request.
  debug,

  /// Start-up, migrations, shutdown.
  info,

  /// Conditions that need attention but do not fail requests.
  warn,

  /// Failures.
  error;

  /// Parse a level name.
  ///
  /// Description: accepts debug, info, warn and error (lower case).
  ///
  /// Business Justification: the value of AAAS_LOG_LEVEL.
  ///
  /// Parameters:
  /// - [name]: level name, null when unset.
  /// - [fallback]: level used when [name] is null or unknown.
  ///
  /// Returns: the level.
  ///
  /// Errors: none (the fallback for unknown names). Side Effects: none.
  /// Complexity: O(1). Thread Safety: safe. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `Level.parse('debug', Level.info) == Level.debug`.
  ///
  /// See Also: [Logger].
  static Level parse(String? name, Level fallback) {
    for (final level in Level.values) {
      if (level.name == name) {
        return level;
      }
    }
    return fallback;
  }
}

/// Escape a string for use inside a JSON string literal.
///
/// Description: the result of `jsonEncode` without the surrounding quotes:
/// the quote, the backslash and every control character are escaped.
///
/// Business Justification: log lines and problem details must stay valid
/// JSON whatever a request path or an SQLite message contains.
///
/// Parameters:
/// - [text]: any string.
///
/// Returns: the escaped text, without surrounding quotes.
///
/// Errors: none. Side Effects: none. Complexity: O(n) time and memory.
/// Thread Safety: safe (pure). Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
///
/// Example: `jsonEscape('a"b') == r'a\"b'`.
///
/// See Also: [Logger.write].
String jsonEscape(String text) {
  final encoded = jsonEncode(text);
  return encoded.substring(1, encoded.length - 1);
}

/// Current UTC time as ISO 8601 with milliseconds.
///
/// Business Justification: the ts field of every line (CLAUDE.md 6.1).
///
/// Returns: for example `2026-10-18T12:00:00.000Z`.
///
/// Errors: none. Side Effects: reads the clock. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `final ts = timestamp();`
///
/// See Also: [Logger.write].
String timestamp() {
  final iso = DateTime.now().toUtc().toIso8601String();
  return '${iso.substring(0, 23)}Z';
}

/// Writer of JSON log lines for one service.
///
/// Business Justification: structured logs are collected by the
/// observability stack (CLAUDE.md 6.1, P7.1).
///
/// Thread Safety: one isolate; every line is written with one call.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
class Logger {
  /// Create a logger.
  ///
  /// Business Justification: every line names its service (CLAUDE.md 6.1).
  ///
  /// Parameters:
  /// - [service]: service name, for example digit-5.
  /// - [threshold]: lines below this level are not written.
  /// - [sink]: destination of the lines; stdout by default.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: not applicable. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final log = Logger('digit-5', Level.info);`
  ///
  /// See Also: [write].
  Logger(this.service, this.threshold, {StringSink? sink})
    : _sink = sink ?? stdout;

  /// Service name written in every line.
  final String service;

  /// Minimum level written.
  final Level threshold;

  /// Destination of the lines.
  final StringSink _sink;

  /// Write one JSON log line.
  ///
  /// Description: nothing is written when [level] is below [threshold].
  /// The detail field is present only when [detail] is not null.
  ///
  /// Business Justification: structured logs (CLAUDE.md 6.1).
  ///
  /// Parameters:
  /// - [level]: severity of the line.
  /// - [msg]: message, constant per call site.
  /// - [traceId]: trace id of the request, null when none.
  /// - [spanId]: caller's span id, null when none.
  /// - [detail]: variable part, null when none.
  ///
  /// Errors: none. Side Effects: writes to the sink. Complexity: O(n) in
  /// the length of the line. Thread Safety: one isolate. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `log.write(Level.info, 'listening', detail: 'port 8080');`
  ///
  /// See Also: [jsonEscape].
  void write(
    Level level,
    String msg, {
    String? traceId,
    String? spanId,
    String? detail,
  }) {
    if (level.index < threshold.index) {
      return;
    }
    final line = StringBuffer()
      ..write('{"ts":"${timestamp()}","level":"${level.name}",')
      ..write('"service":${jsonEncode(service)},"msg":${jsonEncode(msg)},')
      ..write('"taskId":null,"traceId":${jsonEncode(traceId)},')
      ..write('"spanId":${jsonEncode(spanId)}');
    if (detail != null) {
      line.write(',"detail":${jsonEncode(detail)}');
    }
    line.write('}');
    _sink.writeln(line);
  }
}
