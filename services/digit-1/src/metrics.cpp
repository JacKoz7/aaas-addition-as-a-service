// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/metrics.cpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Prometheus metrics of the digit service.
// Related Docs:    src/metrics.hpp

/**
 * @file metrics.cpp
 * @brief Implementation of metrics.hpp.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#include "metrics.hpp"

#include <format>
#include <iterator>
#include <string_view>
#include <utility>

namespace aaas::digit {

namespace {

/// @brief Values of the `endpoint` label, indexed by Endpoint.
constexpr std::array<std::string_view, 2> endpoint_names = {"value", "next"};

/// @brief Values of the `outcome` label, indexed by Outcome.
constexpr std::array<std::string_view, 2> outcome_names = {"ok", "error"};

} // namespace

Metrics::Metrics(int digit, std::string version) : digit_(digit), version_(std::move(version)) {}

void Metrics::count(Endpoint endpoint, Outcome outcome) {
  requests_.at(static_cast<std::size_t>(endpoint))
      .at(static_cast<std::size_t>(outcome))
      .fetch_add(1, std::memory_order_relaxed);
}

std::uint64_t Metrics::get(Endpoint endpoint, Outcome outcome) const {
  return requests_.at(static_cast<std::size_t>(endpoint))
      .at(static_cast<std::size_t>(outcome))
      .load(std::memory_order_relaxed);
}

std::string Metrics::render() const {
  std::string text = "# HELP digit_requests_total Requests answered by the digit service.\n"
                     "# TYPE digit_requests_total counter\n";
  auto out = std::back_inserter(text);
  for (std::size_t e = 0; e < endpoints; ++e) {
    for (std::size_t o = 0; o < outcomes; ++o) {
      out = std::format_to(out, "digit_requests_total{{digit=\"{}\",endpoint=\"{}\",outcome=\"{}\"}} {}\n", digit_,
                           endpoint_names.at(e), outcome_names.at(o),
                           requests_.at(e).at(o).load(std::memory_order_relaxed));
    }
  }
  std::format_to(out,
                 "# HELP digit_build_info Build information of the digit service.\n"
                 "# TYPE digit_build_info gauge\n"
                 "digit_build_info{{digit=\"{}\",version=\"{}\"}} 1\n",
                 digit_, version_);
  return text;
}

} // namespace aaas::digit
