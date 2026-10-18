/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/api.c
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         The HTTP contract of the digit service as a pure function.
 * Related Docs:    src/api.h, contracts/http/digit.yaml
 */

/**
 * @file api.c
 * @brief Implementation of api.h.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#include "api.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "log.h"
#include "store.h"

/** @brief Media type of JSON bodies. */
static const char *const JSON = "application/json";

/** @brief Media type of problem details (RFC 9457). */
static const char *const PROBLEM_JSON = "application/problem+json";

/** @brief Media type of the Prometheus text exposition. */
static const char *const PROMETHEUS_TEXT = "text/plain; version=0.0.4";

/** @brief Paths of the contract; other methods on them answer 405. */
static const char *const KNOWN_PATHS[] = {"/value", "/next", "/health", "/metrics"};

/**
 * @brief Fill a reply with problem details (RFC 9457).
 *
 * @details `type` is `about:blank`; @p detail is JSON-escaped.
 *
 * @par Business Justification
 * Every AaaS error is problem details (CLAUDE.md 4.1).
 *
 * @param[out] reply Reply to fill.
 * @param status HTTP status.
 * @param title Short summary of the problem type.
 * @param detail Explanation of this occurrence.
 *
 * @par Errors
 * None (truncates an overlong detail).
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the detail length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * problem(reply, 404, "Not Found", "no such path");
 * @endcode
 * @see api_handle
 */
static void problem(struct api_reply *reply, int status, const char *title, const char *detail) {
  char escaped[512];
  json_escape(escaped, sizeof escaped, detail);
  reply->status = status;
  reply->content_type = PROBLEM_JSON;
  (void)snprintf(reply->body, sizeof reply->body,
                 "{\"type\":\"about:blank\",\"title\":\"%s\",\"status\":%d,\"detail\":\"%s\"}", title, status, escaped);
}

/**
 * @brief Read the digit row and check that it names the configured digit.
 *
 * @details A failure is logged at error level.
 *
 * @par Business Justification
 * A service must never answer for another digit, for example after its
 * volume was mixed up with another service's.
 *
 * @param ctx Service context.
 * @param[out] row Receives the row on success.
 * @return true when the row was read and matches the configured digit.
 *
 * @par Errors
 * false when the database cannot be read or the row names another digit.
 * @par Side Effects
 * One SELECT; logs failures.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * As the connection.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * struct digit_row row;
 * if (read_row(ctx, &row)) { ... }
 * @endcode
 * @see store_read
 */
static bool read_row(const struct api_context *ctx, struct digit_row *row) {
  if (store_read(ctx->db, row) != 0) {
    log_write(LVL_ERROR, "cannot read the digit from the database", NULL, NULL, sqlite3_errmsg(ctx->db));
    return false;
  }
  if (row->digit != ctx->digit) {
    log_write(LVL_ERROR, "the database holds another digit", NULL, NULL, NULL);
    return false;
  }
  return true;
}

/**
 * @brief Answer GET /value or GET /next.
 *
 * @details Reads the row on every call; 503 problem details when it cannot
 * be read. Counts the request in the metrics.
 *
 * @par Business Justification
 * The arithmetic of the digit (CLAUDE.md 4.4).
 *
 * @param ctx Service context.
 * @param endpoint Which of the two operations.
 * @param[out] reply Reply to fill.
 *
 * @par Errors
 * None (503 reply on failure).
 * @par Side Effects
 * One SELECT; one counter increment.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * As the connection.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * answer_digit(ctx, ENDPOINT_NEXT, reply);
 * @endcode
 * @see api_handle
 */
static void answer_digit(const struct api_context *ctx, enum metrics_endpoint endpoint, struct api_reply *reply) {
  struct digit_row row;
  if (!read_row(ctx, &row)) {
    metrics_count(ctx->metrics, endpoint, OUTCOME_ERROR);
    problem(reply, 503, "Service Unavailable", "the digit cannot be read from the database; retry the call");
    return;
  }
  metrics_count(ctx->metrics, endpoint, OUTCOME_OK);
  reply->status = 200;
  reply->content_type = JSON;
  if (endpoint == ENDPOINT_VALUE) {
    (void)snprintf(reply->body, sizeof reply->body, "{\"digit\":%d,\"value\":%d}", row.digit, row.value);
  } else {
    (void)snprintf(reply->body, sizeof reply->body, "{\"digit\":%d,\"next\":%d,\"carry\":%s}", row.digit, row.next,
                   row.carry ? "true" : "false");
  }
}

void api_handle(const struct api_context *ctx, const char *method, const char *path, struct api_reply *reply) {
  memset(reply, 0, sizeof *reply);
  bool known = false;
  for (size_t i = 0; i < sizeof KNOWN_PATHS / sizeof KNOWN_PATHS[0]; i++) {
    known = known || strcmp(path, KNOWN_PATHS[i]) == 0;
  }
  if (!known) {
    problem(reply, 404, "Not Found", "the digit service has no such path");
    return;
  }
  if (strcmp(method, "GET") != 0) {
    problem(reply, 405, "Method Not Allowed", "only GET is allowed on this path");
    reply->allow = "GET";
    return;
  }
  if (strcmp(path, "/value") == 0) {
    answer_digit(ctx, ENDPOINT_VALUE, reply);
  } else if (strcmp(path, "/next") == 0) {
    answer_digit(ctx, ENDPOINT_NEXT, reply);
  } else if (strcmp(path, "/health") == 0) {
    struct digit_row row;
    bool ok = read_row(ctx, &row);
    reply->status = ok ? 200 : 503;
    reply->content_type = JSON;
    (void)snprintf(reply->body, sizeof reply->body, "{\"status\":\"%s\",\"checks\":{\"database\":\"%s\"}}",
                   ok ? "ok" : "error", ok ? "ok" : "error");
  } else {
    reply->content_type = PROMETHEUS_TEXT;
    if (metrics_render(ctx->metrics, reply->body, sizeof reply->body) < 0) {
      problem(reply, 500, "Internal Server Error", "the metrics do not fit the reply buffer");
    } else {
      reply->status = 200;
    }
  }
}
