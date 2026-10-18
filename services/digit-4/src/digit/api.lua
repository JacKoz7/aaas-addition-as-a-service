-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          src/digit/api.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         The HTTP contract of the digit service as a function
--                  from (method, path) to a reply: routing, JSON bodies,
--                  problem details, health and metrics.
-- Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

--- Request handling of contracts/http/digit.yaml, independent of the HTTP
-- server.
--
-- digit.http passes each request to Api:handle and sends the reply it
-- returns; the unit tests call Api:handle directly.
--
-- A reply is a table with status (integer), content_type (string), allow
-- (string or nil, 405 only) and body (string).
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @module digit.api

local log = require("digit.log")

local M = {}

-- The class of this module, defined below its constructor.
local Api

--- Media type of JSON bodies.
-- Owner: AEC. Since: digit-4 0.1.0.
local JSON_TYPE = "application/json"

--- Media type of problem details (RFC 9457).
-- Owner: AEC. Since: digit-4 0.1.0.
local PROBLEM_TYPE = "application/problem+json"

--- Media type of the Prometheus text exposition.
-- Owner: AEC. Since: digit-4 0.1.0.
local PROMETHEUS_TYPE = "text/plain; version=0.0.4"

--- Paths of the contract.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @table PATHS
local PATHS = { ["/value"] = true, ["/next"] = true, ["/health"] = true, ["/metrics"] = true }

--- Build a problem details reply (RFC 9457).
--
-- Description: type is about:blank; title and detail are JSON-escaped.
--
-- Business Justification: every AaaS error is problem details
-- (CLAUDE.md 4.1).
--
-- Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @tparam integer status HTTP status
-- @tparam string title short summary of the problem type
-- @tparam string detail explanation of this occurrence
-- @treturn table the reply with content type application/problem+json
-- @usage local reply = api.problem(404, "Not Found", "no such path")
-- @see Api:handle
function M.problem(status, title, detail)
  return {
    status = status,
    content_type = PROBLEM_TYPE,
    body = string.format(
      '{"type":"about:blank","title":"%s","status":%d,"detail":"%s"}',
      log.json_escape(title),
      status,
      log.json_escape(detail)
    ),
  }
end

--- Bind the contract to a database and counters; nothing is read until the
-- first request.
--
-- Business Justification: one contract object per service process.
--
-- Errors: none. Side Effects: none. Complexity: O(1).
-- Thread Safety: not applicable. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam Store store open, migrated database of the service
-- @tparam integer digit the digit the service represents, 0..9
-- @tparam Metrics metrics counters updated by /value and /next
-- @treturn Api the contract
-- @usage local a = api.new(store, 4, metrics)
-- @see Api:handle
function M.new(store, digit, metrics)
  return setmetatable({ store = store, digit = digit, metrics = metrics }, Api)
end

--- The digit contract over one database.
--
-- Description: holds references to the store and the metrics, which must
-- outlive it.
--
-- Business Justification: the single implementation of the contract that
-- every digit request goes through; the value is read on every request,
-- never cached or hard-coded (CLAUDE.md 4.4).
--
-- Thread Safety: safe; the service runs one OS thread and handle never
-- yields. Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @type Api
Api = {}
Api.__index = Api

--- Read the digit row and check that it names the configured digit.
--
-- Description: a failure is logged at error level.
--
-- Business Justification: a service must never answer for another digit,
-- for example after its volume was mixed up with another one.
--
-- Errors: nil on failure. Side Effects: one SELECT; logs failures.
-- Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @treturn ?table the row, nil on failure
-- @usage local row = self:read_row()
-- @see digit.store
function Api:read_row()
  local row, err = self.store:read()
  if row == nil then
    log.write("error", "cannot read the digit from the database", nil, nil, err)
    return nil
  end
  if row.digit ~= self.digit then
    log.write("error", "the database holds another digit")
    return nil
  end
  return row
end

--- Answer GET /value or GET /next.
--
-- Description: reads the row on every call; 503 problem details when it
-- cannot be read. Counts the request in the metrics.
--
-- Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).
--
-- Errors: none (503 reply on failure). Side Effects: one SELECT; one
-- counter increment. Complexity: O(1). Thread Safety: safe. Owner: AEC.
-- Since: digit-4 0.1.0.
-- @tparam string endpoint "value" or "next"
-- @treturn table the reply
-- @usage local reply = self:answer_digit("next")
-- @see Api:handle
function Api:answer_digit(endpoint)
  local row = self:read_row()
  if row == nil then
    self.metrics:count(endpoint, "error")
    return M.problem(503, "Service Unavailable", "the digit cannot be read from the database; retry the call")
  end
  self.metrics:count(endpoint, "ok")
  local body
  if endpoint == "value" then
    body = string.format('{"digit":%d,"value":%d}', row.digit, row.value)
  else
    body = string.format('{"digit":%d,"next":%d,"carry":%s}', row.digit, row.next, tostring(row.carry))
  end
  return { status = 200, content_type = JSON_TYPE, body = body }
end

--- Answer one request according to contracts/http/digit.yaml.
--
-- Description: GET /value answers 200 with digit and value; GET /next 200
-- with digit, next and carry, both from the database; GET /health 200 with
-- status ok and checks.database ok when the row can be read and names the
-- configured digit, otherwise 503 with error; GET /metrics 200 Prometheus
-- text; another method on one of these paths 405 problem details with
-- Allow: GET; any other path 404 problem details. When the row cannot be
-- read or names another digit, /value and /next answer 503 problem details
-- and count an error.
--
-- Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).
--
-- Errors: none (404, 405 or 503 replies). Side Effects: reads the
-- database; updates the metrics; logs database failures.
-- Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string method HTTP method, as received
-- @tparam string path request path without the query string
-- @treturn table the reply
-- @usage local reply = a:handle("GET", "/next")
-- @see problem
function Api:handle(method, path)
  if not PATHS[path] then
    return M.problem(404, "Not Found", "the digit service has no such path")
  end
  if method ~= "GET" then
    local reply = M.problem(405, "Method Not Allowed", "only GET is allowed on this path")
    reply.allow = "GET"
    return reply
  end
  if path == "/value" then
    return self:answer_digit("value")
  end
  if path == "/next" then
    return self:answer_digit("next")
  end
  if path == "/health" then
    if self:read_row() ~= nil then
      return { status = 200, content_type = JSON_TYPE, body = '{"status":"ok","checks":{"database":"ok"}}' }
    end
    return { status = 503, content_type = JSON_TYPE, body = '{"status":"error","checks":{"database":"error"}}' }
  end
  return { status = 200, content_type = PROMETHEUS_TYPE, body = self.metrics:render() }
end

return M
