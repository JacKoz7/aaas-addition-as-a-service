-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          src/digit/log.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Structured JSON log lines on stdout with the fields of
--                  CLAUDE.md 6.1, and the JSON string escaping shared with
--                  the response bodies.
-- Related Docs:    CLAUDE.md 6.1, services/digit-4/README.md, ADR-0022

--- Structured JSON logging of the digit service.
--
-- Every line is one JSON object with `ts`, `level`, `service`, `msg`,
-- `taskId`, `traceId`, `spanId` and an optional `detail` (CLAUDE.md 6.1).
-- `taskId` is always null: a digit request does not carry a task.
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @module digit.log

local gettimeofday = require("posix.sys.time").gettimeofday

local M = {}

--- Names of the levels, in increasing severity.
-- Thread Safety: read-only. Owner: AEC. Since: digit-4 0.1.0.
-- @table LEVELS
local LEVELS = { "debug", "info", "warn", "error" }

--- Severity of each level name (debug 1 .. error 4).
-- Thread Safety: read-only. Owner: AEC. Since: digit-4 0.1.0.
-- @table SEVERITY
local SEVERITY = { debug = 1, info = 2, warn = 3, error = 4 }

--- Escapes of the characters that JSON strings may not hold literally.
-- Thread Safety: read-only. Owner: AEC. Since: digit-4 0.1.0.
-- @table ESCAPES
local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

--- Logger state: service name and minimum severity written.
-- Changed only by `init`. Owner: AEC. Since: digit-4 0.1.0.
-- @table state
-- @field service service name written in every line
-- @field threshold minimum severity written (1..4)
local state = { service = "digit-4", threshold = SEVERITY.info }

--- Escape a string for use inside a JSON string literal.
--
-- Description: escapes the quote, the backslash, newline, carriage return
-- and tab with their short forms, and every other control character below
-- 0x20 as \u00XX. Other bytes, including UTF-8 sequences, are kept.
--
-- Business Justification: log lines and problem details must stay valid
-- JSON whatever a request path or an SQLite message contains.
--
-- Errors: none. Side Effects: none. Complexity: O(n) time and memory.
-- Thread Safety: safe (pure). Owner: Arithmetic Excellence Center (AEC).
-- Since: digit-4 0.1.0.
-- @tparam string text any byte string
-- @treturn string the escaped text, without surrounding quotes
-- @usage log.json_escape('a"b') --> 'a\\"b'
-- @see write
function M.json_escape(text)
  return (text:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end))
end

--- Parse a level name.
--
-- Description: accepts debug, info, warn and error (lower case).
--
-- Business Justification: AAAS_LOG_LEVEL selects the verbosity without a
-- rebuild.
--
-- Errors: none (the fallback for unknown names). Side Effects: none.
-- Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam ?string name level name, nil when unset
-- @tparam string fallback level used when name is nil or unknown
-- @treturn string a valid level name
-- @usage log.parse_level(os.getenv("AAAS_LOG_LEVEL"), "info")
-- @see init
function M.parse_level(name, fallback)
  if name ~= nil and SEVERITY[name] then
    return name
  end
  return fallback
end

--- Set the service name and the minimum level.
--
-- Description: lines below the level are not written.
--
-- Business Justification: every line names its service (CLAUDE.md 6.1).
--
-- Errors: none. Side Effects: changes the logger state. Complexity: O(1).
-- Thread Safety: call once at start-up. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string service service name, for example digit-4
-- @tparam string level a level name accepted by parse_level
-- @usage log.init("digit-4", "info")
-- @see parse_level
function M.init(service, level)
  state.service = service
  state.threshold = SEVERITY[level] or SEVERITY.info
end

--- Current UTC time as ISO 8601 with milliseconds.
--
-- Business Justification: the ts field of every line (CLAUDE.md 6.1).
--
-- Errors: none. Side Effects: reads the clock. Complexity: O(1).
-- Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @treturn string for example 2026-10-18T12:00:00.000Z
-- @usage local ts = timestamp()
-- @see write
local function timestamp()
  local now = gettimeofday()
  return os.date("!%Y-%m-%dT%H:%M:%S", now.tv_sec) .. string.format(".%03dZ", now.tv_usec // 1000)
end

--- A JSON string literal, or null for nil.
--
-- Business Justification: absent ids are written as null, not as "".
--
-- Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam ?string value text or nil
-- @treturn string a JSON value
-- @usage quoted(nil) --> 'null'
-- @see json_escape
local function quoted(value)
  if value == nil then
    return "null"
  end
  return '"' .. M.json_escape(value) .. '"'
end

--- Write one JSON log line on stdout.
--
-- Description: nothing is written when level is below the threshold set by
-- init. The detail field is present only when detail is not nil. stdout is
-- flushed after every line.
--
-- Business Justification: structured logs are collected by the
-- observability stack (CLAUDE.md 6.1, P7.1).
--
-- Errors: none (a failed write is ignored). Side Effects: writes to stdout.
-- Complexity: O(n) in the length of the line. Thread Safety: safe (a line
-- is written with one call). Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string level debug, info, warn or error
-- @tparam string msg message, constant per call site
-- @tparam ?string trace_id trace id of the request, nil when none
-- @tparam ?string span_id caller's span id, nil when none
-- @tparam ?string detail variable part, nil when none
-- @usage log.write("info", "listening", nil, nil, "port 8080")
-- @see init
function M.write(level, msg, trace_id, span_id, detail)
  if SEVERITY[level] < state.threshold then
    return
  end
  local line = string.format(
    '{"ts":"%s","level":"%s","service":%s,"msg":%s,"taskId":null,"traceId":%s,"spanId":%s',
    timestamp(),
    level,
    quoted(state.service),
    quoted(msg),
    quoted(trace_id),
    quoted(span_id)
  )
  if detail ~= nil then
    line = line .. ',"detail":' .. quoted(detail)
  end
  io.stdout:write(line, "}\n")
  io.stdout:flush()
end

--- The level names, in increasing severity (for the tests).
-- Owner: AEC. Since: digit-4 0.1.0.
-- @table levels
M.levels = LEVELS

return M
