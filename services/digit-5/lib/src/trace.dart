// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          lib/src/trace.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Parsing of the W3C traceparent header, so that log lines
//                  carry the caller's trace and span ids.
// Related Docs:    CLAUDE.md 6.1, contracts/http/digit.yaml

/// W3C Trace Context (traceparent) parsing.
///
/// Until the instrumentation of P7.2 the service creates no spans; it
/// continues the caller's trace in its logs.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

/// Pattern of a traceparent value: version, trace id, parent id and flags
/// as 2, 32, 16 and 2 lowercase hex digits.
///
/// Owner: AEC. Since: digit-5 0.1.0.
final RegExp _pattern = RegExp(
  r'^([0-9a-f]{2})-([0-9a-f]{32})-([0-9a-f]{16})-[0-9a-f]{2}$',
);

/// Pattern of an id made of zeros only, which W3C Trace Context forbids.
///
/// Owner: AEC. Since: digit-5 0.1.0.
final RegExp _zeros = RegExp(r'^0+$');

/// Trace and parent span ids of a valid traceparent header.
///
/// Business Justification: logs of a digit call join the trace of the
/// addition (CLAUDE.md 6.1).
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
class TraceContext {
  /// Create a context from already validated ids.
  ///
  /// Parameters:
  /// - [traceId]: 32 lowercase hex digits.
  /// - [spanId]: 16 lowercase hex digits.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `const TraceContext('4bf9...4736', '00f0...02b7')`.
  ///
  /// See Also: [TraceContext.parse].
  const TraceContext(this.traceId, this.spanId);

  /// 32 lowercase hex digits.
  final String traceId;

  /// 16 lowercase hex digits of the caller's span.
  final String spanId;

  /// Parse a traceparent header value.
  ///
  /// Description: accepts version-traceid-parentid-flags with 2, 32, 16
  /// and 2 lowercase hex digits, a version other than ff, and ids that are
  /// not all zeros (W3C Trace Context, level 1). Anything else, including
  /// null, is rejected.
  ///
  /// Business Justification: only well-formed ids reach the logs.
  ///
  /// Parameters:
  /// - [header]: header value, null when absent.
  ///
  /// Returns: the context, or null when the header is invalid.
  ///
  /// Errors: none (null for invalid input). Side Effects: none.
  /// Complexity: O(1). Thread Safety: safe (pure). Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `TraceContext.parse('00-4bf9...4736-00f0...02b7-01')`.
  ///
  /// See Also: [TraceContext].
  static TraceContext? parse(String? header) {
    final match = header == null ? null : _pattern.firstMatch(header);
    if (match == null ||
        match[1] == 'ff' ||
        _zeros.hasMatch(match[2]!) ||
        _zeros.hasMatch(match[3]!)) {
      return null;
    }
    return TraceContext(match[2]!, match[3]!);
  }
}
