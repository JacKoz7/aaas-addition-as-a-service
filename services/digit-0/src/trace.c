/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/trace.c
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         Parsing of the W3C `traceparent` header.
 * Related Docs:    src/trace.h
 */

/**
 * @file trace.c
 * @brief Implementation of trace.h.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#include "trace.h"

#include <string.h>

/** @brief Length of a version 00 `traceparent` value. */
static const size_t TRACEPARENT_LENGTH = 55;

/**
 * @brief Whether @p n characters of @p s are lowercase hex digits and not
 *        all zeros (when @p nonzero).
 *
 * @details Used for each dash-separated part of the header.
 *
 * @par Business Justification
 * W3C Trace Context forbids upper case and all-zero ids.
 *
 * @param s Start of the part.
 * @param n Number of characters.
 * @param nonzero Also require a non-zero digit.
 * @return true when the part is valid.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n).
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * is_hex("00f067aa0ba902b7", 16, true); // true
 * @endcode
 * @see trace_parse
 */
static bool is_hex(const char *s, size_t n, bool nonzero) {
  bool any = false;
  for (size_t i = 0; i < n; i++) {
    char c = s[i];
    if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f'))) {
      return false;
    }
    any = any || c != '0';
  }
  return any || !nonzero;
}

bool trace_parse(const char *header, struct trace_context *out) {
  if (header == NULL || strlen(header) != TRACEPARENT_LENGTH || header[2] != '-' || header[35] != '-' ||
      header[52] != '-') {
    return false;
  }
  if (!is_hex(header, 2, false) || strncmp(header, "ff", 2) == 0 || !is_hex(header + 3, 32, true) ||
      !is_hex(header + 36, 16, true) || !is_hex(header + 53, 2, false)) {
    return false;
  }
  memcpy(out->trace_id, header + 3, 32);
  out->trace_id[32] = '\0';
  memcpy(out->span_id, header + 36, 16);
  out->span_id[16] = '\0';
  return true;
}
