/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/main.c
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Entry point of the digit-0 service: configuration from
 *                  the environment, database migrations, the HTTP server
 *                  (libmicrohttpd) on port 8080 and graceful shutdown.
 * Related Docs:    services/digit-0/README.md, CLAUDE.md 4.4, 6.1, ADR-0022
 */

/**
 * @file main.c
 * @brief Process entry point: configuration, start-up and shutdown.
 *
 * @details Start-up: read the configuration (AAAS_BOOTSTRAP=env until
 * P5.2), open and migrate the database, check that it holds the configured
 * digit, then serve HTTP until SIGTERM or SIGINT. Shutdown stops accepting
 * connections, lets the server thread finish and closes the database, well
 * within the 10 s of CLAUDE.md 6.1.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#include <microhttpd.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "api.h"
#include "log.h"
#include "metrics.h"
#include "store.h"
#include "trace.h"

/** @brief Version of the service (SemVer, docs/CHANGELOG.md). */
static const char *const SERVICE_VERSION = "0.1.0";

/** @brief Seconds after which an idle connection is closed. */
static const unsigned int CONNECTION_TIMEOUT_S = 10;

/**
 * @brief Configuration of the process, from the environment.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @see load_config
 */
struct config {
  const char *service;        /**< AAAS_SERVICE (default `digit-0`). */
  const char *db_path;        /**< AAAS_DB_PATH (default `/data/digit-0.db`). */
  const char *migrations_dir; /**< AAAS_MIGRATIONS_DIR (default `/app/migrations`). */
  int digit;                  /**< AAAS_DIGIT, 0..9 (default 0). */
  unsigned short port;        /**< AAAS_HTTP_PORT (default 8080). */
};

/**
 * @brief Value of an environment variable, or a default when unset or empty.
 *
 * @details Thin wrapper over getenv.
 *
 * @par Business Justification
 * Configuration comes only from the environment (CLAUDE.md 6.1).
 *
 * @param name Variable name.
 * @param fallback Value used when the variable is unset or empty.
 * @return The value.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Reads the environment.
 * @par Complexity
 * O(e) in the size of the environment.
 * @par Thread Safety
 * Safe while no thread modifies the environment.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * const char *path = env_or("AAAS_DB_PATH", "/data/digit-0.db");
 * @endcode
 * @see load_config
 */
static const char *env_or(const char *name, const char *fallback) {
  const char *value = getenv(name);
  return value != NULL && value[0] != '\0' ? value : fallback;
}

/**
 * @brief Parse a decimal integer in [min, max].
 *
 * @details The whole string must be the number.
 *
 * @par Business Justification
 * Rejects misconfiguration (for example a port of 0) at start-up.
 *
 * @param text Text to parse.
 * @param min Smallest accepted value.
 * @param max Largest accepted value.
 * @param[out] out Receives the value on success.
 * @return 0 on success, -1 otherwise.
 *
 * @par Errors
 * -1 for non-numeric text or a value out of range.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the text length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * long port;
 * parse_int("8080", 1, 65535, &port);
 * @endcode
 * @see load_config
 */
static int parse_int(const char *text, long min, long max, long *out) {
  char *end = NULL;
  long value = strtol(text, &end, 10);
  if (end == text || *end != '\0' || value < min || value > max) {
    return -1;
  }
  *out = value;
  return 0;
}

/**
 * @brief Read the configuration from the environment.
 *
 * @details Only AAAS_BOOTSTRAP=env is available until the config server and
 * OpenBao exist (P5.2, P5.3); `platform` is refused.
 *
 * @par Business Justification
 * CLAUDE.md 3 ("Platform at the start of every service") and 6.1.
 *
 * @param[out] cfg Receives the configuration.
 * @return 0 on success, -1 on invalid configuration (logged).
 *
 * @par Errors
 * -1 for AAAS_BOOTSTRAP other than `env`, or an invalid AAAS_DIGIT or
 * AAAS_HTTP_PORT.
 * @par Side Effects
 * Reads the environment; logs errors.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not safe; call once at start-up.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * struct config cfg;
 * if (load_config(&cfg) != 0) return 1;
 * @endcode
 * @see main
 */
static int load_config(struct config *cfg) {
  const char *bootstrap = env_or("AAAS_BOOTSTRAP", "env");
  if (strcmp(bootstrap, "env") != 0) {
    log_write(LVL_ERROR, "unsupported AAAS_BOOTSTRAP; only env exists before P5.2", NULL, NULL, bootstrap);
    return -1;
  }
  long digit;
  long port;
  if (parse_int(env_or("AAAS_DIGIT", "0"), 0, 9, &digit) != 0) {
    log_write(LVL_ERROR, "AAAS_DIGIT must be 0..9", NULL, NULL, getenv("AAAS_DIGIT"));
    return -1;
  }
  if (parse_int(env_or("AAAS_HTTP_PORT", "8080"), 1, 65535, &port) != 0) {
    log_write(LVL_ERROR, "AAAS_HTTP_PORT must be 1..65535", NULL, NULL, getenv("AAAS_HTTP_PORT"));
    return -1;
  }
  cfg->service = env_or("AAAS_SERVICE", "digit-0");
  cfg->db_path = env_or("AAAS_DB_PATH", "/data/digit-0.db");
  cfg->migrations_dir = env_or("AAAS_MIGRATIONS_DIR", "/app/migrations");
  cfg->digit = (int)digit;
  cfg->port = (unsigned short)port;
  return 0;
}

/**
 * @brief libmicrohttpd access handler: answer one request through api_handle.
 *
 * @details Called at least twice per request: the first call only marks
 * the request (headers received), further calls discard any request body,
 * and the final call queues the reply. A valid `traceparent` header puts the
 * caller's trace into the debug log line of the request.
 *
 * @par Business Justification
 * Bridges the server library to the library-independent contract code.
 *
 * @param cls The api_context.
 * @param connection The connection.
 * @param url Request path (without query string).
 * @param method HTTP method.
 * @param version HTTP version (unused).
 * @param upload_data Chunk of the request body (ignored).
 * @param[in,out] upload_data_size Size of the chunk; set to 0 to consume it.
 * @param[in,out] req_cls Per-request state (a marker after the first call).
 * @return MHD_YES to continue, MHD_NO to close the connection.
 *
 * @par Errors
 * MHD_NO when the reply cannot be created or queued.
 * @par Side Effects
 * Database read, metrics update, debug log, network write.
 * @par Complexity
 * O(1) per call.
 * @par Thread Safety
 * Runs on the single server thread only.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * MHD_start_daemon(..., &handle_request, &ctx, MHD_OPTION_END);
 * @endcode
 * @see api_handle
 */
static enum MHD_Result handle_request(void *cls, struct MHD_Connection *connection, const char *url, const char *method,
                                      const char *version, const char *upload_data, size_t *upload_data_size,
                                      void **req_cls) {
  static int marker;
  (void)version;
  (void)upload_data;
  if (*req_cls == NULL) {
    *req_cls = &marker;
    return MHD_YES;
  }
  if (*upload_data_size != 0) {
    *upload_data_size = 0;
    return MHD_YES;
  }

  struct api_reply reply;
  api_handle((const struct api_context *)cls, method, url, &reply);

  struct trace_context trace;
  const char *header = MHD_lookup_connection_value(connection, MHD_HEADER_KIND, "traceparent");
  bool traced = trace_parse(header, &trace);
  char detail[128];
  (void)snprintf(detail, sizeof detail, "%s %s -> %d", method, url, reply.status);
  log_write(LVL_DEBUG, "request answered", traced ? trace.trace_id : NULL, traced ? trace.span_id : NULL, detail);

  struct MHD_Response *response = MHD_create_response_from_buffer_copy(strlen(reply.body), reply.body);
  if (response == NULL) {
    return MHD_NO;
  }
  MHD_add_response_header(response, MHD_HTTP_HEADER_CONTENT_TYPE, reply.content_type);
  if (reply.allow != NULL) {
    MHD_add_response_header(response, MHD_HTTP_HEADER_ALLOW, reply.allow);
  }
  enum MHD_Result result = MHD_queue_response(connection, (unsigned int)reply.status, response);
  MHD_destroy_response(response);
  return result;
}

/**
 * @brief Run the service.
 *
 * @details See the file documentation. SIGTERM and SIGINT are blocked
 * before the server thread starts, so that only this thread receives them
 * through sigwait().
 *
 * @par Business Justification
 * Digit 0 as a service (CLAUDE.md 2, row 13).
 *
 * @return 0 after a clean shutdown, 1 when start-up fails.
 *
 * @par Errors
 * 1 for invalid configuration, an unopenable or unmigratable database, a
 * database holding another digit, or a port that cannot be bound.
 * @par Side Effects
 * Opens the database, binds the port, writes logs.
 * @par Complexity
 * Not applicable.
 * @par Thread Safety
 * Not applicable (process entry point).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * AAAS_DB_PATH=/tmp/d.db AAAS_MIGRATIONS_DIR=migrations ./digit-0
 * @endcode
 * @see load_config, handle_request
 */
int main(void) {
  log_init(env_or("AAAS_SERVICE", "digit-0"), log_level_parse(getenv("AAAS_LOG_LEVEL"), LVL_INFO));
  struct config cfg;
  if (load_config(&cfg) != 0) {
    return 1;
  }
  sqlite3 *db = NULL;
  int applied = 0;
  struct digit_row row;
  if (store_open(cfg.db_path, &db) != 0 || store_migrate(db, cfg.migrations_dir, &applied) != 0) {
    store_close(db);
    return 1;
  }
  if (store_read(db, &row) != 0 || row.digit != cfg.digit) {
    log_write(LVL_ERROR, "the database does not hold the configured digit", NULL, NULL, cfg.db_path);
    store_close(db);
    return 1;
  }

  struct metrics metrics;
  metrics_init(&metrics, cfg.digit, SERVICE_VERSION);
  struct api_context ctx = {.db = db, .digit = cfg.digit, .metrics = &metrics};

  sigset_t signals;
  sigemptyset(&signals);
  sigaddset(&signals, SIGTERM);
  sigaddset(&signals, SIGINT);
  pthread_sigmask(SIG_BLOCK, &signals, NULL);

  struct MHD_Daemon *daemon =
      MHD_start_daemon(MHD_USE_INTERNAL_POLLING_THREAD, cfg.port, NULL, NULL, &handle_request, &ctx,
                       MHD_OPTION_CONNECTION_TIMEOUT, CONNECTION_TIMEOUT_S, MHD_OPTION_END);
  if (daemon == NULL) {
    log_write(LVL_ERROR, "cannot start the HTTP server", NULL, NULL, NULL);
    store_close(db);
    return 1;
  }
  char detail[64];
  (void)snprintf(detail, sizeof detail, "port %u, digit %d, version %s", cfg.port, cfg.digit, SERVICE_VERSION);
  log_write(LVL_INFO, "listening", NULL, NULL, detail);

  int received = 0;
  sigwait(&signals, &received);
  log_write(LVL_INFO, "shutting down", NULL, NULL, received == SIGTERM ? "SIGTERM" : "SIGINT");
  MHD_quiesce_daemon(daemon);
  MHD_stop_daemon(daemon);
  store_close(db);
  log_write(LVL_INFO, "stopped", NULL, NULL, NULL);
  return 0;
}
