/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/api.h
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         The HTTP contract of the digit service as a pure
 *                  function from (method, path) to a reply: routing, JSON
 *                  bodies, problem details, health and metrics.
 * Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022
 */

/**
 * @file api.h
 * @brief Request handling of contracts/http/digit.yaml, independent of the
 *        HTTP server library.
 *
 * @details main.c passes each request to api_handle() and sends the reply
 * it fills in; the unit tests call api_handle() directly.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#ifndef DIGIT_API_H
#define DIGIT_API_H

#include <sqlite3.h>

#include "metrics.h"

/** @brief Capacity of a reply body in bytes (the metrics text is the largest). */
#define API_BODY_CAPACITY 4096

/**
 * @brief What api_handle() needs from the service.
 *
 * @par Thread Safety
 * Used by one thread at a time (single-threaded server).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @see api_handle
 */
struct api_context {
  sqlite3 *db;             /**< Open, migrated database of the service. */
  int digit;               /**< The digit the service represents (AAAS_DIGIT). */
  struct metrics *metrics; /**< Counters updated by /value and /next. */
};

/**
 * @brief An HTTP reply to send.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @see api_handle
 */
struct api_reply {
  int status;                   /**< HTTP status code. */
  const char *content_type;     /**< Value of Content-Type (static string). */
  const char *allow;            /**< Value of Allow, or NULL when not sent. */
  char body[API_BODY_CAPACITY]; /**< Response body, NUL-terminated. */
};

/**
 * @brief Answer one request according to contracts/http/digit.yaml.
 *
 * @details
 * - `GET /value` → 200 `{"digit":d,"value":v}` from the database;
 * - `GET /next` → 200 `{"digit":d,"next":n,"carry":c}` from the database;
 * - `GET /health` → 200 `{"status":"ok","checks":{"database":"ok"}}` when
 *   the row can be read and names the configured digit, otherwise 503 with
 *   `status` and `checks.database` set to `error`;
 * - `GET /metrics` → 200 Prometheus text;
 * - another method on one of these paths → 405 problem with `Allow: GET`;
 * - any other path → 404 problem.
 *
 * When the row cannot be read, or names another digit than the configured
 * one, `/value` and `/next` answer 503 problem details. `/value` and `/next`
 * are counted in the metrics with their outcome.
 *
 * @par Business Justification
 * The single implementation of the contract that every digit request goes
 * through; the value is read on every request, never cached or hard-coded
 * (CLAUDE.md 4.4).
 *
 * @param ctx Service context.
 * @param method HTTP method, upper case.
 * @param path Request path without the query string.
 * @param[out] reply Filled in completely.
 *
 * @par Errors
 * None: failures become 404, 405 or 503 replies.
 * @par Side Effects
 * Reads the database (/value, /next, /health); updates the metrics.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not safe; one request at a time (the server is single-threaded).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * struct api_reply reply;
 * api_handle(&ctx, "GET", "/next", &reply); // 200 {"digit":0,"next":1,"carry":false}
 * @endcode
 * @see store_read, metrics_render
 */
void api_handle(const struct api_context *ctx, const char *method, const char *path, struct api_reply *reply);

#endif /* DIGIT_API_H */
