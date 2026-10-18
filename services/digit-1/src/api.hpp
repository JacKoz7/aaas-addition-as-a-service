// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/api.hpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The HTTP contract of the digit service as a function
//                  from (method, path) to a reply: routing, JSON bodies,
//                  problem details, health and metrics.
// Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

/**
 * @file api.hpp
 * @brief Request handling of contracts/http/digit.yaml, independent of the
 *        HTTP server library.
 *
 * @details main.cpp passes each request to Api::handle() and sends the
 * reply it returns; the unit tests call Api::handle() directly.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#ifndef DIGIT_API_HPP
#define DIGIT_API_HPP

#include <mutex>
#include <optional>
#include <string>
#include <string_view>

#include "metrics.hpp"
#include "store.hpp"

namespace aaas::digit {

/**
 * @brief An HTTP reply to send.
 *
 * @par Thread Safety
 * Plain value; safe to copy.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @see Api::handle
 */
struct Reply {
  int status = 0;                   ///< HTTP status code.
  std::string content_type;         ///< Value of Content-Type.
  std::optional<std::string> allow; ///< Value of Allow, when sent (405 only).
  std::string body;                 ///< Response body.
};

/**
 * @brief The digit contract over one database.
 *
 * @details Holds references to the store and the metrics, which must
 * outlive it.
 *
 * @par Business Justification
 * The single implementation of the contract that every digit request goes
 * through; the value is read on every request, never cached or hard-coded
 * (CLAUDE.md 4.4).
 *
 * @par Thread Safety
 * Safe: handle() serialises database access with a mutex, so the server may
 * call it from several worker threads.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @see Store, Metrics
 */
class Api {
public:
  /**
   * @brief Bind the contract to a database and counters.
   *
   * @details Nothing is read until the first request.
   *
   * @par Business Justification
   * The service answers for exactly one digit, the configured one.
   *
   * @param store Open, migrated database of the service.
   * @param digit The digit the service represents (AAAS_DIGIT), 0..9.
   * @param metrics Counters updated by /value and /next.
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
   * Api api(store, 1, metrics);
   * @endcode
   * @see handle
   */
  Api(Store &store, int digit, Metrics &metrics);

  /**
   * @brief Answer one request according to contracts/http/digit.yaml.
   *
   * @details
   * - `GET /value` → 200 `{"digit":d,"value":v}` from the database;
   * - `GET /next` → 200 `{"digit":d,"next":n,"carry":c}` from the database;
   * - `GET /health` → 200 `{"status":"ok","checks":{"database":"ok"}}` when
   *   the row can be read and names the configured digit, otherwise 503
   *   with `status` and `checks.database` set to `error`;
   * - `GET /metrics` → 200 Prometheus text;
   * - another method on one of these paths → 405 problem with `Allow: GET`;
   * - any other path → 404 problem.
   *
   * When the row cannot be read, or names another digit than the
   * configured one, `/value` and `/next` answer 503 problem details.
   * `/value` and `/next` are counted in the metrics with their outcome.
   *
   * @par Business Justification
   * The arithmetic of the digit (CLAUDE.md 4.4).
   *
   * @param method HTTP method, upper case.
   * @param path Request path without the query string.
   * @return The reply.
   *
   * @par Errors
   * None: failures become 404, 405 or 503 replies.
   * @par Side Effects
   * Reads the database (/value, /next, /health); updates the metrics;
   * logs database failures.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Safe (see the class).
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * Reply reply = api.handle("GET", "/next"); // 200 {"digit":1,"next":2,"carry":false}
   * @endcode
   * @see Store::read, Metrics::render
   */
  [[nodiscard]] Reply handle(std::string_view method, std::string_view path);

private:
  /**
   * @brief Read the digit row and check that it names the configured digit.
   *
   * @details A failure is logged at error level.
   *
   * @par Business Justification
   * A service must never answer for another digit, for example after its
   * volume was mixed up with another service's.
   *
   * @return The row, or std::nullopt when it cannot be read or names
   *         another digit.
   *
   * @par Errors
   * None (std::nullopt, see Returns).
   * @par Side Effects
   * One SELECT under the mutex; logs failures.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Safe (holds the mutex).
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * if (auto row = read_row()) { ... }
   * @endcode
   * @see Store::read
   */
  std::optional<DigitRow> read_row();

  /**
   * @brief Answer GET /value or GET /next.
   *
   * @details Reads the row on every call; 503 problem details when it
   * cannot be read. Counts the request in the metrics.
   *
   * @par Business Justification
   * The arithmetic of the digit (CLAUDE.md 4.4).
   *
   * @param endpoint Which of the two operations.
   * @return The reply.
   *
   * @par Errors
   * None (503 reply on failure).
   * @par Side Effects
   * One SELECT; one counter increment.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Safe.
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * Reply reply = answer_digit(Endpoint::next);
   * @endcode
   * @see handle
   */
  Reply answer_digit(Endpoint endpoint);

  Store &store_;     ///< Database of the service.
  int digit_;        ///< The configured digit.
  Metrics &metrics_; ///< Request counters.
  std::mutex mutex_; ///< Serialises use of the single SQLite connection.
};

/**
 * @brief Build a problem details reply (RFC 9457).
 *
 * @details `type` is `about:blank`; strings are JSON-escaped.
 *
 * @par Business Justification
 * Every AaaS error is problem details (CLAUDE.md 4.1).
 *
 * @param status HTTP status.
 * @param title Short summary of the problem type.
 * @param detail Explanation of this occurrence.
 * @return The reply, Content-Type `application/problem+json`.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the length of the strings.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * Reply reply = problem(404, "Not Found", "the digit service has no such path");
 * @endcode
 * @see Api::handle
 */
[[nodiscard]] Reply problem(int status, std::string_view title, std::string_view detail);

} // namespace aaas::digit

#endif // DIGIT_API_HPP
