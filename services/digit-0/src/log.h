/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/log.h
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Structured JSON logging on stdout with the fields of
 *                  CLAUDE.md 6.1, and JSON string escaping.
 * Related Docs:    CLAUDE.md 6.1, services/digit-0/README.md
 */

/**
 * @file log.h
 * @brief Structured JSON logs (one object per line on stdout).
 *
 * @details Every line has `ts`, `level`, `service`, `msg`, `taskId`,
 * `traceId` and `spanId` (CLAUDE.md 6.1), plus `detail` when given. A digit
 * call carries no task, so `taskId` is always null; `traceId` and `spanId`
 * come from the caller's `traceparent` when present.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#ifndef DIGIT_LOG_H
#define DIGIT_LOG_H

#include <stddef.h>

/**
 * @brief Severity of a log line, in increasing order.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
enum log_level {
  LVL_DEBUG, /**< Per-request details; off by default. */
  LVL_INFO,  /**< Lifecycle events: start, migrations, shutdown. */
  LVL_WARN,  /**< Recoverable problems. */
  LVL_ERROR, /**< Failures: unreadable database, failed start. */
  LVL_OFF    /**< Threshold only: writes nothing (used by the unit tests). */
};

/**
 * @brief Configure the service name and the minimum level written.
 *
 * @details Lines below @p threshold are dropped. Until called, the service
 * name is `digit` and the threshold is info.
 *
 * @par Business Justification
 * Every line names its service; the level is configurable per environment.
 *
 * @param service Service name, for example `digit-0`; must outlive all
 *        logging (a string literal or environment value).
 * @param threshold Minimum level written.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Sets process-wide logging state.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not safe; call once at start-up.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * log_init("digit-0", LVL_INFO);
 * @endcode
 * @see log_write
 */
void log_init(const char *service, enum log_level threshold);

/**
 * @brief Parse a level name (`debug`, `info`, `warn`, `error`).
 *
 * @details Case-sensitive; any other value, including NULL, yields
 * @p fallback.
 *
 * @par Business Justification
 * The level comes from the environment variable AAAS_LOG_LEVEL.
 *
 * @param name Level name or NULL.
 * @param fallback Level returned for unknown names.
 * @return The parsed level.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * enum log_level level = log_level_parse(getenv("AAAS_LOG_LEVEL"), LVL_INFO);
 * @endcode
 * @see log_init
 */
enum log_level log_level_parse(const char *name, enum log_level fallback);

/**
 * @brief Write one JSON log line to stdout.
 *
 * @details The timestamp is UTC with milliseconds (ISO 8601). Strings are
 * JSON-escaped; NULL @p trace_id, @p span_id or @p detail become null (the
 * `detail` field is omitted when NULL). The line is flushed immediately.
 *
 * @par Business Justification
 * Logs are collected by Loki from stdout (P7.1) and correlated by trace.
 *
 * @param level Severity.
 * @param msg Message, English.
 * @param trace_id Trace id (32 lowercase hex) or NULL.
 * @param span_id Span id of the caller (16 lowercase hex) or NULL.
 * @param detail Extra detail (error text, file name) or NULL.
 *
 * @par Errors
 * None (a failed write to stdout is ignored).
 * @par Side Effects
 * Writes to stdout.
 * @par Complexity
 * O(n) in the length of the strings.
 * @par Thread Safety
 * Safe: one stdio call per line.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * log_write(LVL_INFO, "listening", NULL, NULL, "port 8080");
 * @endcode
 * @see log_init
 */
void log_write(enum log_level level, const char *msg, const char *trace_id, const char *span_id, const char *detail);

/**
 * @brief Escape a string for the inside of a JSON string literal.
 *
 * @details Escapes the double quote and the backslash with a backslash,
 * newline, carriage return and tab by their short escapes, and the other
 * control characters as a `u00XX` escape. The output is always
 * NUL-terminated and truncated to fit @p capacity.
 *
 * @par Business Justification
 * Log messages and problem details may contain arbitrary text.
 *
 * @param[out] out Output buffer.
 * @param capacity Size of @p out in bytes, at least 1.
 * @param in Input string.
 * @return Length of the written output, excluding the NUL.
 *
 * @par Errors
 * None (truncates).
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the input length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * char buf[64];
 * size_t n = json_escape(buf, sizeof buf, "plain text"); // n == 10
 * @endcode
 * @see log_write
 */
size_t json_escape(char *out, size_t capacity, const char *in);

#endif /* DIGIT_LOG_H */
