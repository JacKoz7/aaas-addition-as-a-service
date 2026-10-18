/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/log.c
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Structured JSON logging and JSON string escaping.
 * Related Docs:    src/log.h, CLAUDE.md 6.1
 */

/**
 * @file log.c
 * @brief Implementation of log.h.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#include "log.h"

#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <time.h>

/** @brief Service name written in every line (set by log_init). */
static const char *log_service = "digit";

/** @brief Minimum level written (set by log_init). */
static enum log_level log_threshold = LVL_INFO;

/** @brief Names of the levels, indexed by enum log_level. */
static const char *const LEVEL_NAMES[] = {"debug", "info", "warn", "error"};

void log_init(const char *service, enum log_level threshold) {
  log_service = service;
  log_threshold = threshold;
}

enum log_level log_level_parse(const char *name, enum log_level fallback) {
  if (name == NULL) {
    return fallback;
  }
  for (int level = LVL_DEBUG; level <= LVL_ERROR; level++) {
    if (strcmp(name, LEVEL_NAMES[level]) == 0) {
      return (enum log_level)level;
    }
  }
  return fallback;
}

size_t json_escape(char *out, size_t capacity, const char *in) {
  size_t len = 0;
  for (const unsigned char *p = (const unsigned char *)in; *p != '\0'; p++) {
    char chunk[8];
    switch (*p) {
    case '"':
      strcpy(chunk, "\\\"");
      break;
    case '\\':
      strcpy(chunk, "\\\\");
      break;
    case '\n':
      strcpy(chunk, "\\n");
      break;
    case '\r':
      strcpy(chunk, "\\r");
      break;
    case '\t':
      strcpy(chunk, "\\t");
      break;
    default:
      if (*p < 0x20) {
        (void)snprintf(chunk, sizeof chunk, "\\u%04x", *p);
      } else {
        chunk[0] = (char)*p;
        chunk[1] = '\0';
      }
    }
    size_t n = strlen(chunk);
    if (len + n >= capacity) {
      break;
    }
    memcpy(out + len, chunk, n);
    len += n;
  }
  out[len] = '\0';
  return len;
}

/**
 * @brief Write `"key":"value"` or `"key":null` into a buffer.
 *
 * @details Escapes @p value; appends nothing when the buffer is full.
 *
 * @par Business Justification
 * Shared by the optional fields of log_write.
 *
 * @param[out] buf Buffer.
 * @param size Size of @p buf.
 * @param[in,out] used Bytes used so far; advanced by the written length.
 * @param key Field name (plain ASCII).
 * @param value Field value or NULL.
 *
 * @par Errors
 * None (truncates).
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the value length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * append_field(line, sizeof line, &used, "traceId", NULL); // ,"traceId":null
 * @endcode
 * @see log_write
 */
static void append_field(char *buf, size_t size, size_t *used, const char *key, const char *value) {
  char escaped[512];
  int n;
  if (value == NULL) {
    n = snprintf(buf + *used, size - *used, ",\"%s\":null", key);
  } else {
    json_escape(escaped, sizeof escaped, value);
    n = snprintf(buf + *used, size - *used, ",\"%s\":\"%s\"", key, escaped);
  }
  if (n > 0 && (size_t)n < size - *used) {
    *used += (size_t)n;
  }
}

void log_write(enum log_level level, const char *msg, const char *trace_id, const char *span_id, const char *detail) {
  if (level < log_threshold) {
    return;
  }
  struct timeval now;
  gettimeofday(&now, NULL);
  struct tm utc;
  (void)gmtime_r(&now.tv_sec, &utc);
  char ts[32];
  (void)strftime(ts, sizeof ts, "%Y-%m-%dT%H:%M:%S", &utc);

  char line[2048];
  char escaped[512];
  json_escape(escaped, sizeof escaped, msg);
  int n = snprintf(line, sizeof line, "{\"ts\":\"%s.%03ldZ\",\"level\":\"%s\",\"service\":\"%s\",\"msg\":\"%s\"", ts,
                   (long)(now.tv_usec / 1000), LEVEL_NAMES[level], log_service, escaped);
  size_t used = n > 0 && (size_t)n < sizeof line ? (size_t)n : 0;
  append_field(line, sizeof line, &used, "taskId", NULL);
  append_field(line, sizeof line, &used, "traceId", trace_id);
  append_field(line, sizeof line, &used, "spanId", span_id);
  if (detail != NULL) {
    append_field(line, sizeof line, &used, "detail", detail);
  }
  (void)fprintf(stdout, "%s}\n", line);
  (void)fflush(stdout);
}
