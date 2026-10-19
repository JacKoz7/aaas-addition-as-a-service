// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          src/DigitService/Trace.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Parsing of the W3C traceparent header, so that log lines
//                  carry the caller's trace and span ids.
// Related Docs:    CLAUDE.md 6.1, contracts/http/digit.yaml

/// Trace and parent span ids of a valid W3C `traceparent` header.
///
/// Description: until the instrumentation of P7.2 the service creates no
/// spans; it continues the caller's trace in its logs.
///
/// Business Justification: logs of a digit call join the trace of the
/// addition (CLAUDE.md 6.1).
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public struct TraceContext: Equatable, Sendable {
  /// 32 lowercase hex digits.
  public let traceId: String
  /// 16 lowercase hex digits of the caller's span.
  public let spanId: String

  /// Parse a `traceparent` header value.
  ///
  /// Description: accepts version-traceid-parentid-flags with 2, 32, 16
  /// and 2 lowercase hex digits, a version other than ff, and ids that are
  /// not all zeros (W3C Trace Context, level 1). Anything else, including
  /// nil, is rejected.
  ///
  /// Business Justification: only well-formed ids reach the logs.
  ///
  /// - Parameter header: Header value, nil when absent.
  /// - Returns: The context, or nil when the header is invalid.
  ///
  /// Errors: none (nil for invalid input). Side Effects: none.
  /// Complexity: O(1). Thread Safety: safe (pure). Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `TraceContext.parse("00-4bf9...4736-00f0...02b7-01")`.
  ///
  /// See Also: ``isHex(_:nonZero:)``.
  public static func parse(_ header: String?) -> TraceContext? {
    guard let header else { return nil }
    let parts = header.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 4,
      parts[0].count == 2, parts[1].count == 32, parts[2].count == 16, parts[3].count == 2,
      isHex(parts[0], nonZero: false), parts[0] != "ff",
      isHex(parts[1], nonZero: true), isHex(parts[2], nonZero: true),
      isHex(parts[3], nonZero: false)
    else { return nil }
    return TraceContext(traceId: String(parts[1]), spanId: String(parts[2]))
  }

  /// Whether a part is lowercase hex and, when `nonZero`, not all zeros.
  ///
  /// Business Justification: W3C Trace Context forbids upper case and
  /// all-zero ids.
  ///
  /// - Parameters:
  ///   - part: One dash-separated part of the header.
  ///   - nonZero: Also require a non-zero digit.
  /// - Returns: True when the part is valid.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
  /// safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `isHex("00f067aa0ba902b7", nonZero: true) == true`.
  ///
  /// See Also: ``parse(_:)``.
  static func isHex(_ part: Substring, nonZero: Bool) -> Bool {
    let digits = part.utf8
    guard digits.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
      return false
    }
    return !nonZero || digits.contains { $0 != 48 }
  }
}
