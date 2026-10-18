// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/trace.hpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Parsing of the W3C `traceparent` header, so that log
//                  lines carry the caller's trace and span ids.
// Related Docs:    CLAUDE.md 6.1, contracts/http/digit.yaml

/**
 * @file trace.hpp
 * @brief W3C Trace Context (`traceparent`) parsing.
 *
 * @details Until the instrumentation of P7.2 the service creates no spans;
 * it continues the caller's trace in its logs.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#ifndef DIGIT_TRACE_HPP
#define DIGIT_TRACE_HPP

#include <optional>
#include <string>
#include <string_view>

/**
 * @brief The digit-1 service.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
namespace aaas::digit {

/**
 * @brief Trace and parent span ids of a `traceparent` header.
 *
 * @par Thread Safety
 * Plain value; safe to copy.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @see parse_traceparent
 */
struct TraceContext {
  std::string trace_id; ///< 32 lowercase hex digits.
  std::string span_id;  ///< 16 lowercase hex digits of the caller's span.
};

/**
 * @brief Parse a `traceparent` header value.
 *
 * @details Accepts `<version>-<trace-id>-<parent-id>-<flags>` with 2, 32,
 * 16 and 2 lowercase hex digits, a version other than `ff`, and ids that
 * are not all zeros (W3C Trace Context, level 1). Anything else is
 * rejected.
 *
 * @par Business Justification
 * Logs of a digit call join the trace of the addition (CLAUDE.md 6.1).
 *
 * @param header Header value (empty when the header is absent).
 * @return The ids, or std::nullopt when the header is invalid.
 *
 * @par Errors
 * None (std::nullopt for invalid input).
 * @par Side Effects
 * None.
 * @par Complexity
 * O(1) (fixed length).
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * auto ctx = parse_traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
 * // ctx->span_id == "00f067aa0ba902b7"
 * @endcode
 * @see logging::write
 */
[[nodiscard]] std::optional<TraceContext> parse_traceparent(std::string_view header);

} // namespace aaas::digit

#endif // DIGIT_TRACE_HPP
