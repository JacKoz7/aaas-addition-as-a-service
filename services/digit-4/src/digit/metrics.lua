-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          src/digit/metrics.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Prometheus metrics of the digit service: the request
--                  counter shared by all ten digit services and the build
--                  information.
-- Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

--- Request counter digit_requests_total and its exposition.
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @module digit.metrics

local M = {}

-- The class of this module, defined below its constructor.
local Metrics

--- Values of the endpoint label, in exposition order.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @table ENDPOINTS
local ENDPOINTS = { "value", "next" }

--- Values of the outcome label, in exposition order: answered 200 (ok) or
-- 503 (error, database unavailable).
-- Owner: AEC. Since: digit-4 0.1.0.
-- @table OUTCOMES
local OUTCOMES = { "ok", "error" }

--- Create zeroed counters.
--
-- Business Justification: the counters of one service process.
--
-- Errors: none. Side Effects: none. Complexity: O(1).
-- Thread Safety: not applicable. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam integer digit the service's digit, 0..9
-- @tparam string version service version
-- @treturn Metrics the counters
-- @usage local m = metrics.new(4, "0.1.0")
-- @see Metrics:count
function M.new(digit, version)
  local requests = {}
  for _, endpoint in ipairs(ENDPOINTS) do
    requests[endpoint] = { ok = 0, error = 0 }
  end
  return setmetatable({ digit = digit, version = version, requests = requests }, Metrics)
end

--- Counters of one service process.
--
-- Description: every sample exists from the start (value 0).
--
-- Business Justification: one dashboard shows the traffic of all ten digit
-- services (P7.3).
--
-- Thread Safety: safe; the service runs one OS thread and no counter
-- update yields. Owner: Arithmetic Excellence Center (AEC).
-- Since: digit-4 0.1.0.
-- @type Metrics
Metrics = {}
Metrics.__index = Metrics

--- Count one answered request.
--
-- Business Justification: traffic and errors per digit.
--
-- Errors: raises when endpoint or outcome is not a label value.
-- Side Effects: increments one counter. Complexity: O(1).
-- Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string endpoint "value" or "next"
-- @tparam string outcome "ok" or "error"
-- @usage m:count("next", "ok")
-- @see Metrics:render
function Metrics:count(endpoint, outcome)
  local samples = self.requests[endpoint]
  samples[outcome] = samples[outcome] + 1
end

--- Current value of one sample (used by the unit tests).
--
-- Business Justification: tests check the counter without parsing text.
--
-- Errors: raises when endpoint is not a label value. Side Effects: none.
-- Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string endpoint "value" or "next"
-- @tparam string outcome "ok" or "error"
-- @treturn integer number of counted requests
-- @usage m:get("next", "error")
-- @see Metrics:count
function Metrics:get(endpoint, outcome)
  return self.requests[endpoint][outcome]
end

--- Render the Prometheus text exposition (format 0.0.4).
--
-- Description: digit_requests_total with labels digit, endpoint and
-- outcome (all four samples) and digit_build_info with labels digit and
-- version, value 1.
--
-- Business Justification: GET /metrics of the contract.
--
-- Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @treturn string the exposition text
-- @usage local text = m:render()
-- @see Metrics:count
function Metrics:render()
  local lines = {
    "# HELP digit_requests_total Requests answered by the digit service.",
    "# TYPE digit_requests_total counter",
  }
  for _, endpoint in ipairs(ENDPOINTS) do
    for _, outcome in ipairs(OUTCOMES) do
      lines[#lines + 1] = string.format(
        'digit_requests_total{digit="%d",endpoint="%s",outcome="%s"} %d',
        self.digit,
        endpoint,
        outcome,
        self.requests[endpoint][outcome]
      )
    end
  end
  lines[#lines + 1] = "# HELP digit_build_info Build information of the digit service."
  lines[#lines + 1] = "# TYPE digit_build_info gauge"
  lines[#lines + 1] = string.format('digit_build_info{digit="%d",version="%s"} 1', self.digit, self.version)
  return table.concat(lines, "\n") .. "\n"
end

return M
