// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/metrics.hpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Prometheus metrics of the digit service: the request
//                  counter shared by all ten digit services and the build
//                  information.
// Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

/**
 * @file metrics.hpp
 * @brief Request counter `digit_requests_total` and its exposition.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#ifndef DIGIT_METRICS_HPP
#define DIGIT_METRICS_HPP

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <string>

namespace aaas::digit {

/**
 * @brief Arithmetic endpoint, label `endpoint` of the counter.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
enum class Endpoint : std::uint8_t {
  value, ///< GET /value.
  next   ///< GET /next.
};

/**
 * @brief Outcome of a request, label `outcome` of the counter.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
enum class Outcome : std::uint8_t {
  ok,   ///< Answered 200.
  error ///< Answered 503 (database unavailable).
};

/**
 * @brief Counters of one service process.
 *
 * @details Every sample of the contract exists from the start (value 0).
 *
 * @par Business Justification
 * One dashboard shows the traffic of all ten digit services (P7.3).
 *
 * @par Thread Safety
 * Safe: the counters are atomic (relaxed ordering, they are statistics).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @see Api
 */
class Metrics {
public:
  /**
   * @brief Create zeroed counters.
   *
   * @details Values for the `digit` label and for `digit_build_info`.
   *
   * @par Business Justification
   * The labels identify the service on the shared dashboard.
   *
   * @param digit The service's digit, 0..9.
   * @param version Service version.
   *
   * @par Errors
   * None.
   * @par Side Effects
   * None.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Not applicable (constructor).
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * Metrics metrics(1, "0.1.0");
   * @endcode
   * @see count
   */
  Metrics(int digit, std::string version);

  /**
   * @brief Count one answered request.
   *
   * @details Increments the sample of (@p endpoint, @p outcome).
   *
   * @par Business Justification
   * Traffic and errors per digit (CLAUDE.md 4.4).
   *
   * @param endpoint Endpoint answered.
   * @param outcome Outcome of the request.
   *
   * @par Errors
   * None.
   * @par Side Effects
   * Increments one counter.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Safe (atomic).
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * metrics.count(Endpoint::next, Outcome::ok);
   * @endcode
   * @see render
   */
  void count(Endpoint endpoint, Outcome outcome);

  /**
   * @brief Current value of one sample.
   *
   * @details Used by the unit tests.
   *
   * @par Business Justification
   * Makes the counters observable without parsing the exposition.
   *
   * @param endpoint Endpoint.
   * @param outcome Outcome.
   * @return Number of counted requests.
   *
   * @par Errors
   * None.
   * @par Side Effects
   * None.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Safe (atomic).
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * std::uint64_t n = metrics.get(Endpoint::next, Outcome::error);
   * @endcode
   * @see count
   */
  [[nodiscard]] std::uint64_t get(Endpoint endpoint, Outcome outcome) const;

  /**
   * @brief Render the Prometheus text exposition (format 0.0.4).
   *
   * @details `digit_requests_total{digit,endpoint,outcome}` (all four
   * samples) and `digit_build_info{digit,version} 1`.
   *
   * @par Business Justification
   * GET /metrics of the contract.
   *
   * @return The exposition text.
   *
   * @par Errors
   * None.
   * @par Side Effects
   * None.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Safe (atomic reads; samples may be from slightly different instants).
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * std::string text = metrics.render();
   * @endcode
   * @see count
   */
  [[nodiscard]] std::string render() const;

private:
  /// @brief Number of Endpoint values.
  static constexpr std::size_t endpoints = 2;
  /// @brief Number of Outcome values.
  static constexpr std::size_t outcomes = 2;

  int digit_;           ///< Value of the `digit` label, 0..9.
  std::string version_; ///< Service version for digit_build_info.
  /// @brief digit_requests_total samples, indexed by endpoint and outcome.
  std::array<std::array<std::atomic<std::uint64_t>, outcomes>, endpoints> requests_{};
};

} // namespace aaas::digit

#endif // DIGIT_METRICS_HPP
