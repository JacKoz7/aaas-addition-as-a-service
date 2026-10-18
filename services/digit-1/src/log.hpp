// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/log.hpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Structured JSON logging on stdout with the fields of
//                  CLAUDE.md 6.1.
// Related Docs:    CLAUDE.md 6.1, services/digit-1/README.md, ADR-0022

/**
 * @file log.hpp
 * @brief Structured JSON logs (one object per line on stdout).
 *
 * @details Every line has `ts`, `level`, `service`, `msg`, `taskId`,
 * `traceId` and `spanId` (CLAUDE.md 6.1), plus `detail` when given. A digit
 * call carries no task, so `taskId` is always null; `traceId` and `spanId`
 * come from the caller's `traceparent` when present.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#ifndef DIGIT_LOG_HPP
#define DIGIT_LOG_HPP

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

#include "trace.hpp"

/**
 * @brief Structured logging of the digit-1 service.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
namespace aaas::digit::logging {

/**
 * @brief Severity of a log line, in increasing order.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
enum class Level : std::uint8_t {
  debug, ///< Per-request details; off by default.
  info,  ///< Lifecycle events: start, migrations, shutdown.
  warn,  ///< Recoverable problems.
  error, ///< Failures: unreadable database, failed start.
  off    ///< Threshold only: writes nothing (used by the unit tests).
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
 * @param service Service name, for example `digit-1`.
 * @param threshold Minimum level written.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Sets process-wide logging state.
 * @par Complexity
 * O(n) in the length of the name.
 * @par Thread Safety
 * Safe (guarded by the logging mutex), but meant to be called once at
 * start-up.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * logging::init("digit-1", logging::Level::info);
 * @endcode
 * @see write
 */
void init(std::string service, Level threshold);

/**
 * @brief Parse a level name (`debug`, `info`, `warn`, `error`).
 *
 * @details Case-sensitive; any other value, including an empty optional,
 * yields @p fallback.
 *
 * @par Business Justification
 * The level comes from the environment variable AAAS_LOG_LEVEL.
 *
 * @param name Level name, or std::nullopt when the variable is unset.
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
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * auto level = logging::parse_level("debug", logging::Level::info); // debug
 * @endcode
 * @see init
 */
[[nodiscard]] Level parse_level(std::optional<std::string_view> name, Level fallback);

/**
 * @brief Write one JSON log line to stdout.
 *
 * @details The timestamp is UTC with milliseconds (ISO 8601). Strings are
 * JSON-escaped by nlohmann::json; invalid UTF-8 is replaced, never thrown.
 * Without @p trace, `traceId` and `spanId` are null; without @p detail the
 * `detail` field is omitted. The line is flushed immediately.
 *
 * @par Business Justification
 * Logs are collected by Loki from stdout (P7.1) and correlated by trace.
 *
 * @param level Severity.
 * @param msg Message, English.
 * @param trace Caller's trace context, or std::nullopt.
 * @param detail Extra detail (error text, file name), or std::nullopt.
 *
 * @par Errors
 * None (a failed write to stdout is ignored).
 * @par Side Effects
 * Writes to stdout.
 * @par Complexity
 * O(n) in the length of the strings.
 * @par Thread Safety
 * Safe: lines of concurrent requests never interleave (one mutex).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * logging::write(logging::Level::info, "listening", std::nullopt, "port 8080");
 * @endcode
 * @see init
 */
void write(Level level, std::string_view msg, const std::optional<TraceContext> &trace = std::nullopt,
           const std::optional<std::string> &detail = std::nullopt);

/**
 * @brief Render one log line as JSON, without the trailing newline.
 *
 * @details The shape written by write(); exposed so that the unit tests can
 * check it without capturing stdout.
 *
 * @par Business Justification
 * The log format is a contract with Loki and the dashboards (P7.1).
 *
 * @param level Severity.
 * @param msg Message.
 * @param trace Caller's trace context, or std::nullopt.
 * @param detail Extra detail, or std::nullopt.
 * @return One JSON object.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Reads the clock.
 * @par Complexity
 * O(n) in the length of the strings.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * std::string line = logging::render(logging::Level::info, "stopped", std::nullopt, std::nullopt);
 * @endcode
 * @see write
 */
[[nodiscard]] std::string render(Level level, std::string_view msg, const std::optional<TraceContext> &trace,
                                 const std::optional<std::string> &detail);

} // namespace aaas::digit::logging

#endif // DIGIT_LOG_HPP
