//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/trace.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Parsing of the W3C `traceparent` header, so request log
////                  lines carry the caller's trace and span identifiers.
//// Related Docs:    CLAUDE.md 6.1, https://www.w3.org/TR/trace-context/
////
//// The W3C trace context of an incoming request.
////
//// The service exports no spans before phase 7 (P7.2); it only copies the
//// caller's identifiers into its debug log lines.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// The trace and parent span identifiers of a `traceparent` header.
///
/// Thread Safety: an immutable value. Owner: Arithmetic Excellence Center
/// (AEC). Since: digit-7 0.1.0.
pub type TraceContext {
  /// A parsed context: 32 and 16 lower-case hexadecimal digits.
  TraceContext(trace_id: String, span_id: String)
}

/// Parse a `traceparent` header value.
///
/// Description: the value must be `version-traceid-spanid-flags` with 2,
/// 32, 16 and 2 lower-case hexadecimal digits; version `ff` and all-zero
/// trace or span identifiers are invalid (W3C Trace Context, 3.2).
/// Business Justification: a malformed header from a caller must not put
/// garbage into the log; it is ignored instead.
/// Parameters: `header` — the header value, `None` when absent.
/// Returns: `Some(context)` or `None` for an absent or invalid header.
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `parse(Some("00-4bf9…4736-00f0…02b7-01"))`.
pub fn parse(header: Option(String)) -> Option(TraceContext) {
  case header {
    None -> None
    Some(value) ->
      case string.split(value, "-") {
        [version, trace_id, span_id, flags] ->
          case
            string.length(version) == 2
            && version != "ff"
            && is_hex(version, False)
            && string.length(trace_id) == 32
            && is_hex(trace_id, True)
            && string.length(span_id) == 16
            && is_hex(span_id, True)
            && string.length(flags) == 2
            && is_hex(flags, False)
          {
            True -> Some(TraceContext(trace_id:, span_id:))
            False -> None
          }
        _ -> None
      }
  }
}

/// Whether a text is lower-case hexadecimal, optionally not all zeros.
///
/// Parameters: `part` — the text; `non_zero` — require a digit other
/// than `0`. Returns: True when it qualifies. Errors: none.
/// Side Effects: none. Complexity: O(n). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `is_hex("00", True) == False`.
fn is_hex(part: String, non_zero: Bool) -> Bool {
  let digits = string.to_graphemes(part)
  list.all(digits, fn(digit) { string.contains("0123456789abcdef", digit) })
  && { !non_zero || list.any(digits, fn(digit) { digit != "0" }) }
}
