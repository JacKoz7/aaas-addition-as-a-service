/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/metrics.h
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Prometheus metrics of the digit service: the request
 *                  counter shared by all ten digit services and the build
 *                  information.
 * Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021
 */

/**
 * @file metrics.h
 * @brief Request counter `digit_requests_total` and its exposition.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#ifndef DIGIT_METRICS_H
#define DIGIT_METRICS_H

#include <stddef.h>
#include <stdint.h>

/**
 * @brief Arithmetic endpoint, label `endpoint` of the counter.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
enum metrics_endpoint {
  ENDPOINT_VALUE, /**< GET /value. */
  ENDPOINT_NEXT,  /**< GET /next. */
  ENDPOINT_COUNT  /**< Number of endpoints (array bound). */
};

/**
 * @brief Outcome of a request, label `outcome` of the counter.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */
enum metrics_outcome {
  OUTCOME_OK,    /**< Answered 200. */
  OUTCOME_ERROR, /**< Answered 503 (database unavailable). */
  OUTCOME_COUNT  /**< Number of outcomes (array bound). */
};

/**
 * @brief Counters of one service process.
 *
 * @details Zero-initialise with `{0}` or metrics_init().
 *
 * @par Thread Safety
 * Not synchronised: the HTTP server of the service runs one thread.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @see metrics_render
 */
struct metrics {
  int digit;                                        /**< Value of the `digit` label, 0..9. */
  const char *version;                              /**< Service version for digit_build_info. */
  uint64_t requests[ENDPOINT_COUNT][OUTCOME_COUNT]; /**< digit_requests_total samples. */
};

/**
 * @brief Initialise the counters of a service.
 *
 * @details Sets every counter to zero.
 *
 * @par Business Justification
 * Every sample of the contract exists from the start (value 0).
 *
 * @param[out] m Counters to initialise.
 * @param digit The service's digit.
 * @param version Service version (string literal).
 *
 * @par Errors
 * None.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not safe; call before serving.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * struct metrics m;
 * metrics_init(&m, 0, "0.1.0");
 * @endcode
 * @see metrics_count
 */
void metrics_init(struct metrics *m, int digit, const char *version);

/**
 * @brief Count one answered request.
 *
 * @details Out-of-range arguments are ignored.
 *
 * @par Business Justification
 * One dashboard shows the traffic of all ten digit services (P7.3).
 *
 * @param m Counters.
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
 * Not synchronised (single-threaded server).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * metrics_count(&m, ENDPOINT_NEXT, OUTCOME_OK);
 * @endcode
 * @see metrics_render
 */
void metrics_count(struct metrics *m, enum metrics_endpoint endpoint, enum metrics_outcome outcome);

/**
 * @brief Render the Prometheus text exposition (format 0.0.4).
 *
 * @details `digit_requests_total{digit,endpoint,outcome}` (all four samples)
 * and `digit_build_info{digit,version} 1`.
 *
 * @par Business Justification
 * GET /metrics of the contract.
 *
 * @param m Counters.
 * @param[out] out Output buffer.
 * @param capacity Size of @p out.
 * @return Length written, or -1 when @p capacity is too small.
 *
 * @par Errors
 * -1 on truncation.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not synchronised (single-threaded server).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * char text[2048];
 * metrics_render(&m, text, sizeof text);
 * @endcode
 * @see metrics_count
 */
int metrics_render(const struct metrics *m, char *out, size_t capacity);

#endif /* DIGIT_METRICS_H */
