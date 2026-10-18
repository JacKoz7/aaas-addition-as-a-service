/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/metrics.c
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Prometheus metrics of the digit service.
 * Related Docs:    src/metrics.h
 */

/**
 * @file metrics.c
 * @brief Implementation of metrics.h.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#include "metrics.h"

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

/** @brief Values of the `endpoint` label, indexed by enum metrics_endpoint. */
static const char *const ENDPOINT_NAMES[ENDPOINT_COUNT] = {"value", "next"};

/** @brief Values of the `outcome` label, indexed by enum metrics_outcome. */
static const char *const OUTCOME_NAMES[OUTCOME_COUNT] = {"ok", "error"};

void metrics_init(struct metrics *m, int digit, const char *version) {
  memset(m, 0, sizeof *m);
  m->digit = digit;
  m->version = version;
}

void metrics_count(struct metrics *m, enum metrics_endpoint endpoint, enum metrics_outcome outcome) {
  if (endpoint < ENDPOINT_COUNT && outcome < OUTCOME_COUNT) {
    m->requests[endpoint][outcome]++;
  }
}

int metrics_render(const struct metrics *m, char *out, size_t capacity) {
  size_t used = 0;
  int n = snprintf(out, capacity,
                   "# HELP digit_requests_total Requests answered by the digit service.\n"
                   "# TYPE digit_requests_total counter\n");
  if (n < 0 || (size_t)n >= capacity) {
    return -1;
  }
  used = (size_t)n;
  for (int e = 0; e < ENDPOINT_COUNT; e++) {
    for (int o = 0; o < OUTCOME_COUNT; o++) {
      n = snprintf(out + used, capacity - used,
                   "digit_requests_total{digit=\"%d\",endpoint=\"%s\",outcome=\"%s\"} %" PRIu64 "\n", m->digit,
                   ENDPOINT_NAMES[e], OUTCOME_NAMES[o], m->requests[e][o]);
      if (n < 0 || (size_t)n >= capacity - used) {
        return -1;
      }
      used += (size_t)n;
    }
  }
  n = snprintf(out + used, capacity - used,
               "# HELP digit_build_info Build information of the digit service.\n"
               "# TYPE digit_build_info gauge\n"
               "digit_build_info{digit=\"%d\",version=\"%s\"} 1\n",
               m->digit, m->version);
  if (n < 0 || (size_t)n >= capacity - used) {
    return -1;
  }
  return (int)(used + (size_t)n);
}
