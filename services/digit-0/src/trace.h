/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/trace.h
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Parsing of the W3C `traceparent` header, so that log
 *                  lines carry the caller's trace and span ids.
 * Related Docs:    CLAUDE.md 6.1, contracts/http/digit.yaml
 */

/**
 * @file trace.h
 * @brief W3C Trace Context (`traceparent`) parsing.
 *
 * @details Until the instrumentation of P7.2 the service creates no spans;
 * it continues the caller's trace in its logs.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#ifndef DIGIT_TRACE_H
#define DIGIT_TRACE_H

#include <stdbool.h>

/**
 * @brief Trace and parent span ids of a `traceparent` header.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @see trace_parse
 */
struct trace_context {
  char trace_id[33]; /**< 32 lowercase hex digits, NUL-terminated. */
  char span_id[17];  /**< 16 lowercase hex digits of the caller's span. */
};

/**
 * @brief Parse a `traceparent` header value.
 *
 * @details Accepts `<version>-<trace-id>-<parent-id>-<flags>` with 2, 32,
 * 16 and 2 lowercase hex digits, a version other than `ff`, and ids that
 * are not all zeros (W3C Trace Context, level 1). Anything else, including
 * NULL, is rejected and @p out is left untouched.
 *
 * @par Business Justification
 * Logs of a digit call join the trace of the addition (CLAUDE.md 6.1).
 *
 * @param header Header value or NULL.
 * @param[out] out Receives the ids when valid.
 * @return true when the header is valid.
 *
 * @par Errors
 * None (false for invalid input).
 * @par Side Effects
 * None.
 * @par Complexity
 * O(1) (fixed length).
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * struct trace_context ctx;
 * trace_parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", &ctx);
 * @endcode
 * @see log_write
 */
bool trace_parse(const char *header, struct trace_context *out);

#endif /* DIGIT_TRACE_H */
