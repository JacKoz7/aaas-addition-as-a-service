// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/api.cpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The HTTP contract of the digit service.
// Related Docs:    src/api.hpp, contracts/http/digit.yaml

/**
 * @file api.cpp
 * @brief Implementation of api.hpp.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#include "api.hpp"

#include <algorithm>
#include <array>
#include <nlohmann/json.hpp>

#include "log.hpp"

namespace aaas::digit {

namespace {

/// @brief Media type of JSON bodies.
constexpr std::string_view json_type = "application/json";

/// @brief Media type of problem details (RFC 9457).
constexpr std::string_view problem_type = "application/problem+json";

/// @brief Media type of the Prometheus text exposition.
constexpr std::string_view prometheus_type = "text/plain; version=0.0.4";

/// @brief Paths of the contract; other methods on them answer 405.
constexpr std::array<std::string_view, 4> known_paths = {"/value", "/next", "/health", "/metrics"};

/// @brief HTTP 200 OK.
constexpr int status_ok = 200;
/// @brief HTTP 404 Not Found.
constexpr int status_not_found = 404;
/// @brief HTTP 405 Method Not Allowed.
constexpr int status_method_not_allowed = 405;
/// @brief HTTP 503 Service Unavailable.
constexpr int status_unavailable = 503;

} // namespace

Reply problem(int status, std::string_view title, std::string_view detail) {
  const nlohmann::ordered_json body = {
      {"type", "about:blank"},
      {"title", title},
      {"status", status},
      {"detail", detail},
  };
  return Reply{.status = status, .content_type = std::string(problem_type), .allow = std::nullopt, .body = body.dump()};
}

Api::Api(Store &store, int digit, Metrics &metrics) : store_(store), digit_(digit), metrics_(metrics) {}

std::optional<DigitRow> Api::read_row() {
  DigitRow row;
  try {
    const std::scoped_lock lock(mutex_);
    row = store_.read();
  } catch (const StoreError &error) {
    logging::write(logging::Level::error, "cannot read the digit from the database", std::nullopt, error.what());
    return std::nullopt;
  }
  if (row.digit != digit_) {
    logging::write(logging::Level::error, "the database holds another digit", std::nullopt, std::nullopt);
    return std::nullopt;
  }
  return row;
}

Reply Api::answer_digit(Endpoint endpoint) {
  const auto row = read_row();
  if (!row) {
    metrics_.count(endpoint, Outcome::error);
    return problem(status_unavailable, "Service Unavailable",
                   "the digit cannot be read from the database; retry the call");
  }
  metrics_.count(endpoint, Outcome::ok);
  nlohmann::ordered_json body;
  if (endpoint == Endpoint::value) {
    body = {{"digit", row->digit}, {"value", row->value}};
  } else {
    body = {{"digit", row->digit}, {"next", row->next}, {"carry", row->carry}};
  }
  return Reply{.status = status_ok, .content_type = std::string(json_type), .allow = std::nullopt, .body = body.dump()};
}

Reply Api::handle(std::string_view method, std::string_view path) {
  if (std::ranges::find(known_paths, path) == known_paths.end()) {
    return problem(status_not_found, "Not Found", "the digit service has no such path");
  }
  if (method != "GET") {
    Reply reply = problem(status_method_not_allowed, "Method Not Allowed", "only GET is allowed on this path");
    reply.allow = "GET";
    return reply;
  }
  if (path == "/value") {
    return answer_digit(Endpoint::value);
  }
  if (path == "/next") {
    return answer_digit(Endpoint::next);
  }
  if (path == "/health") {
    const bool ok = read_row().has_value();
    const nlohmann::ordered_json body = {
        {"status", ok ? "ok" : "error"},
        {"checks", {{"database", ok ? "ok" : "error"}}},
    };
    return Reply{.status = ok ? status_ok : status_unavailable,
                 .content_type = std::string(json_type),
                 .allow = std::nullopt,
                 .body = body.dump()};
  }
  return Reply{.status = status_ok,
               .content_type = std::string(prometheus_type),
               .allow = std::nullopt,
               .body = metrics_.render()};
}

} // namespace aaas::digit
