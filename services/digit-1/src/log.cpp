// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/log.cpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Structured JSON logging on stdout.
// Related Docs:    src/log.hpp, CLAUDE.md 6.1

/**
 * @file log.cpp
 * @brief Implementation of log.hpp.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#include "log.hpp"

#include <array>
#include <chrono>
#include <cstddef>
#include <format>
#include <iostream>
#include <mutex>
#include <nlohmann/json.hpp>
#include <utility>

namespace aaas::digit::logging {

namespace {

/// @brief Names of the levels, indexed by Level (off excluded).
constexpr std::array<std::string_view, 4> level_names = {"debug", "info", "warn", "error"};

/**
 * @brief Process-wide logging state.
 *
 * @par Thread Safety
 * Every access holds @ref mutex.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
struct State {
  std::mutex mutex;              ///< Serialises configuration and writes.
  std::string service = "digit"; ///< Service name written in every line.
  Level threshold = Level::info; ///< Minimum level written.
};

/**
 * @brief The logging state of the process.
 *
 * @details A function-local static, so that it is initialised on first use
 * and never before main().
 *
 * @par Business Justification
 * One configuration for every log line of the process.
 *
 * @return The state.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Initialises the state on the first call.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Safe (C++11 static initialisation).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * const std::scoped_lock lock(state().mutex);
 * @endcode
 * @see init, write
 */
State &state() {
  static State instance;
  return instance;
}

} // namespace

void init(std::string service, Level threshold) {
  auto &s = state();
  const std::scoped_lock lock(s.mutex);
  s.service = std::move(service);
  s.threshold = threshold;
}

Level parse_level(std::optional<std::string_view> name, Level fallback) {
  if (!name) {
    return fallback;
  }
  for (std::size_t i = 0; i < level_names.size(); ++i) {
    if (*name == level_names.at(i)) {
      return static_cast<Level>(i);
    }
  }
  return fallback;
}

std::string render(Level level, std::string_view msg, const std::optional<TraceContext> &trace,
                   const std::optional<std::string> &detail) {
  std::string service;
  {
    auto &s = state();
    const std::scoped_lock lock(s.mutex);
    service = s.service;
  }
  const auto now = std::chrono::floor<std::chrono::milliseconds>(std::chrono::system_clock::now());
  nlohmann::ordered_json line = {
      {"ts", std::format("{:%FT%T}Z", now)},
      {"level", level_names.at(static_cast<std::size_t>(level == Level::off ? Level::error : level))},
      {"service", service},
      {"msg", msg},
      {"taskId", nullptr},
      {"traceId", trace ? nlohmann::ordered_json(trace->trace_id) : nlohmann::ordered_json(nullptr)},
      {"spanId", trace ? nlohmann::ordered_json(trace->span_id) : nlohmann::ordered_json(nullptr)},
  };
  if (detail) {
    line["detail"] = *detail;
  }
  return line.dump(-1, ' ', false, nlohmann::ordered_json::error_handler_t::replace);
}

void write(Level level, std::string_view msg, const std::optional<TraceContext> &trace,
           const std::optional<std::string> &detail) {
  auto &s = state();
  {
    const std::scoped_lock lock(s.mutex);
    if (level < s.threshold || level == Level::off) {
      return;
    }
  }
  const std::string line = render(level, msg, trace, detail);
  const std::scoped_lock lock(s.mutex);
  std::cout << line << '\n' << std::flush;
}

} // namespace aaas::digit::logging
