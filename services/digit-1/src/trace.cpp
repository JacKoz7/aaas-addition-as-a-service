// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/trace.cpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Parsing of the W3C `traceparent` header.
// Related Docs:    src/trace.hpp

/**
 * @file trace.cpp
 * @brief Implementation of trace.hpp.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#include "trace.hpp"

#include <algorithm>
#include <cstddef>

namespace aaas::digit {

namespace {

/// @brief Length of a version 00 `traceparent` value.
constexpr std::size_t traceparent_length = 55;

/**
 * @brief Whether @p part is lowercase hex and, when @p nonzero, not all
 *        zeros.
 *
 * @details Used for each dash-separated part of the header.
 *
 * @par Business Justification
 * W3C Trace Context forbids upper case and all-zero ids.
 *
 * @param part One part of the header.
 * @param nonzero Also require a non-zero digit.
 * @return true when the part is valid.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the part length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * is_hex("00f067aa0ba902b7", true); // true
 * @endcode
 * @see parse_traceparent
 */
bool is_hex(std::string_view part, bool nonzero) {
  const bool hex = std::ranges::all_of(part, [](char c) { return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'); });
  return hex && (!nonzero || std::ranges::any_of(part, [](char c) { return c != '0'; }));
}

} // namespace

std::optional<TraceContext> parse_traceparent(std::string_view header) {
  if (header.size() != traceparent_length || header[2] != '-' || header[35] != '-' || header[52] != '-') {
    return std::nullopt;
  }
  const auto version = header.substr(0, 2);
  const auto trace_id = header.substr(3, 32);
  const auto span_id = header.substr(36, 16);
  if (!is_hex(version, false) || version == "ff" || !is_hex(trace_id, true) || !is_hex(span_id, true) ||
      !is_hex(header.substr(53, 2), false)) {
    return std::nullopt;
  }
  return TraceContext{.trace_id = std::string(trace_id), .span_id = std::string(span_id)};
}

} // namespace aaas::digit
