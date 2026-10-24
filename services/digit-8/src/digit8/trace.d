// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/trace.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Parsing of the W3C `traceparent` header, so request log
//                  lines carry the caller's trace and span identifiers.
// Related Docs:    CLAUDE.md 6.1, https://www.w3.org/TR/trace-context/

/**
 * The W3C trace context of an incoming request.
 *
 * The service exports no spans before phase 7 (P7.2); it only copies the
 * caller's identifiers into its debug log lines.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.trace;

import std.algorithm.searching : all, any;
import std.array : split;
import std.string : representation;
import std.typecons : Nullable, nullable;

/**
 * The trace and parent span identifiers of a `traceparent` header.
 *
 * Thread_Safety: a value type. Owner: Arithmetic Excellence Center (AEC).
 * Since: digit-8 0.1.0.
 */
struct TraceContext
{
    /// 32 lower-case hexadecimal digits, not all zero.
    string traceId;
    /// 16 lower-case hexadecimal digits (the caller's span), not all zero.
    string spanId;
}

/**
 * Parse a `traceparent` header value.
 *
 * Description: the value must be `version-traceid-spanid-flags` with 2,
 * 32, 16 and 2 lower-case hexadecimal digits; version `ff` and all-zero
 * trace or span identifiers are invalid (W3C Trace Context, 3.2).
 *
 * Business_Justification: a malformed header from a caller must not put
 * garbage into the log; it is ignored instead.
 *
 * Params:
 *   header = the header value; `null` when absent.
 * Returns: the context, or an empty `Nullable` for an absent or invalid
 * header.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
Nullable!TraceContext parseTraceparent(string header) pure @safe
{
    if (header is null)
    {
        return Nullable!TraceContext.init;
    }
    auto parts = header.split("-");
    if (parts.length != 4 || parts[0].length != 2 || parts[0] == "ff"
            || !isHex(parts[0], false) || parts[1].length != 32
            || !isHex(parts[1], true) || parts[2].length != 16
            || !isHex(parts[2], true) || parts[3].length != 2 || !isHex(parts[3], false))
    {
        return Nullable!TraceContext.init;
    }
    return nullable(TraceContext(parts[1], parts[2]));
}

///
unittest
{
    auto context = parseTraceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
    assert(!context.isNull);
    assert(context.get.traceId == "4bf92f3577b34da6a3ce929d0e0e4736");
    assert(context.get.spanId == "00f067aa0ba902b7");
    assert(parseTraceparent(null).isNull);
    assert(parseTraceparent("garbage").isNull);
}

/**
 * Whether a text is lower-case hexadecimal, optionally not all zeros.
 *
 * Params:
 *   part = the text.
 *   nonZero = require a digit other than `0`.
 * Returns: true when it qualifies.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
private bool isHex(string part, bool nonZero) pure nothrow @safe @nogc
{
    auto bytes = part.representation;
    return bytes.all!(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))
        && (!nonZero || bytes.any!(c => c != '0'));
}

///
unittest
{
    assert(isHex("0a", false));
    assert(!isHex("00", true));
    assert(!isHex("0A", false));
}
