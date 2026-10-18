-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          src/digit/trace.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Parsing of the W3C traceparent header, so that log lines
--                  carry the caller's trace and span ids.
-- Related Docs:    CLAUDE.md 6.1, contracts/http/digit.yaml

--- W3C Trace Context (traceparent) parsing.
--
-- Until the instrumentation of P7.2 the service creates no spans; it
-- continues the caller's trace in its logs.
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @module digit.trace

local M = {}

--- Pattern of a traceparent value: version, trace id, parent id and flags
-- as 2, 32, 16 and 2 lowercase hex digits.
-- Owner: AEC. Since: digit-4 0.1.0.
local PATTERN = "^(%x%x)%-(" .. string.rep("%x", 32) .. ")%-(" .. string.rep("%x", 16) .. ")%-%x%x$"

--- Parse a traceparent header value.
--
-- Description: accepts version-traceid-parentid-flags with 2, 32, 16 and 2
-- lowercase hex digits, a version other than ff, and ids that are not all
-- zeros (W3C Trace Context, level 1). Anything else, including nil, is
-- rejected.
--
-- Business Justification: logs of a digit call join the trace of the
-- addition (CLAUDE.md 6.1).
--
-- Errors: none (nil for invalid input). Side Effects: none.
-- Complexity: O(1). Thread Safety: safe (pure).
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @tparam ?string header header value, nil when absent
-- @treturn ?string trace id (32 hex digits), nil when invalid
-- @treturn ?string caller's span id (16 hex digits), nil when invalid
-- @usage local trace_id, span_id = trace.parse("00-4bf9...4736-00f0...02b7-01")
function M.parse(header)
  if header == nil or header:find("[A-F]") then
    return nil, nil
  end
  local version, trace_id, span_id = header:match(PATTERN)
  if version == nil or version == "ff" or not trace_id:find("[^0]") or not span_id:find("[^0]") then
    return nil, nil
  end
  return trace_id, span_id
end

return M
