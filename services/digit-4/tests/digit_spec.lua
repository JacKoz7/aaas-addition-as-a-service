-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          tests/digit_spec.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Unit tests of the digit-4 service (busted) against the
--                  real migrations: storage, contract, metrics, trace
--                  context, logging and the HTTP/1.1 transport.
-- Related Docs:    services/digit-4/README.md, contracts/http/digit.yaml,
--                  ADR-0022, ADR-0026

--- Unit tests of the digit-4 service.
--
-- Run by busted in the test stage of the Dockerfile, from the service
-- directory (.busted adds src to the module path).
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @script digit_spec

local api = require("digit.api")
local http = require("digit.http")
local log = require("digit.log")
local metrics = require("digit.metrics")
local store = require("digit.store")
local trace = require("digit.trace")
local stat = require("posix.sys.stat")
local unistd = require("posix.unistd")

--- Directory of the real migrations, relative to the service directory.
-- Owner: AEC. Since: digit-4 0.1.0.
local MIGRATIONS = "migrations"

-- The connection double, defined below its constructor.
local Connection

--- Open an in-memory database migrated with the real migrations.
--
-- Business Justification: every test starts from the shipped schema and
-- seed.
--
-- Errors: fails the test when the migration fails. Side Effects: none
-- outside the in-memory database. Complexity: O(1). Thread Safety: tests
-- run sequentially. Owner: AEC. Since: digit-4 0.1.0.
-- @treturn Store the migrated store
-- @usage local db = migrated()
-- @see digit.store
local function migrated()
  local db = assert(store.open(":memory:"))
  assert.are.equal(1, db:migrate(MIGRATIONS))
  return db
end

--- A contract over a fresh migrated database.
--
-- Business Justification: the subject of the contract tests.
--
-- Errors: as migrated. Side Effects: none. Complexity: O(1).
-- Thread Safety: tests run sequentially. Owner: AEC. Since: digit-4 0.1.0.
-- @treturn Api the contract
-- @treturn Store its database
-- @treturn Metrics its counters
-- @usage local a, db, m = contract()
-- @see migrated
local function contract()
  local db = migrated()
  local m = metrics.new(4, "0.1.0")
  return api.new(db, 4, m), db, m
end

--- Create a double that will deliver input.
--
-- Business Justification: each transport test scripts its client.
--
-- Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: one
-- test at a time. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string input bytes the client sends
-- @treturn Connection the double, with field out (string)
-- @usage local con = connection("GET /value HTTP/1.1\r\n\r\n")
-- @see serve
local function connection(input)
  return setmetatable({ input = input, out = "" }, Connection)
end

--- Serve scripted input with the contract and return what was sent.
--
-- Business Justification: end-to-end tests of the transport.
--
-- Errors: as contract. Side Effects: none. Complexity: O(n).
-- Thread Safety: one test at a time. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string input bytes the client sends
-- @treturn string bytes the service sent
-- @usage local out = serve("GET /next HTTP/1.1\r\n\r\n")
-- @see connection
local function serve(input)
  local a = contract()
  local con = connection(input)
  http.serve_connection(con, function(method, path)
    return a:handle(method, path)
  end, function()
    return false
  end, function() end)
  return con.out
end

--- The status codes of the responses in out, in order.
--
-- Business Justification: compact assertions on pipelined answers.
--
-- Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string out bytes the service sent
-- @treturn table the status codes
-- @usage statuses(out) --> {200, 200}
-- @see serve
local function statuses(out)
  local found = {}
  for status in out:gmatch("HTTP/1%.1 (%d%d%d) ") do
    found[#found + 1] = tonumber(status)
  end
  return found
end

--- A connection double with scripted input.
--
-- Description: replaces a cqueues socket in the transport tests; writes
-- are collected in the field out.
--
-- Business Justification: drives the HTTP transport without sockets.
--
-- Thread Safety: one test at a time. Owner: AEC. Since: digit-4 0.1.0.
-- @type Connection
Connection = {}
Connection.__index = Connection

--- Read like a cqueues socket.
--
-- Description: "*L" returns the next line with its LF, or the rest of the
-- input when no LF is left; a number n returns up to n bytes; both return
-- nil at the end of the input.
--
-- Business Justification: the two read forms the transport uses.
--
-- Errors: none. Side Effects: consumes input. Complexity: O(n).
-- Thread Safety: one test at a time. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string|integer format "*L" or a byte count
-- @treturn ?string the bytes read, nil at the end
-- @usage con:read("*L")
-- @see Connection:write
function Connection:read(format)
  if self.input == "" then
    return nil
  end
  local n = format
  if format == "*L" then
    n = self.input:find("\n", 1, true) or #self.input
  end
  local chunk = self.input:sub(1, n)
  self.input = self.input:sub(n + 1)
  return chunk
end

--- Collect written bytes.
--
-- Business Justification: the tests inspect what the service sent.
--
-- Errors: none. Side Effects: appends to out. Complexity: O(n).
-- Thread Safety: one test at a time. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string bytes bytes to send
-- @treturn Connection the double (success, as a socket returns)
-- @usage con:write("HTTP/1.1 200 OK\r\n")
-- @see Connection:flush
function Connection:write(bytes)
  self.out = self.out .. bytes
  return self
end

--- Flush (nothing is buffered).
--
-- Business Justification: the transport flushes after every reply.
--
-- Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: one
-- test at a time. Owner: AEC. Since: digit-4 0.1.0.
-- @treturn Connection the double (success, as a socket returns)
-- @usage con:flush()
-- @see Connection:write
function Connection:flush()
  return self
end

describe("store", function()
  it("applies the migrations once", function()
    local db = migrated()
    assert.are.equal(0, db:migrate(MIGRATIONS))
    assert.is_true(db:is_applied("0001_digit.sql"))
  end)

  it("reads the seeded row of digit 4", function()
    local row = migrated():read()
    assert.are.same({ digit = 4, value = 4, next = 5, carry = false }, row)
  end)

  it("fails for a missing migrations directory", function()
    local db = assert(store.open(":memory:"))
    local applied, err = db:migrate("/nonexistent")
    assert.is_nil(applied)
    assert.matches("migrations directory", err)
  end)

  it("rolls back a failing migration and does not record it", function()
    local dir = os.tmpname()
    os.remove(dir)
    stat.mkdir(dir)
    local file = assert(io.open(dir .. "/0001_bad.sql", "w"))
    file:write("CREATE TABLE t (x INTEGER); INSERT INTO nope VALUES (1);")
    file:close()
    local db = assert(store.open(":memory:"))
    local applied, err = db:migrate(dir)
    os.remove(dir .. "/0001_bad.sql")
    unistd.rmdir(dir)
    assert.is_nil(applied)
    assert.matches("0001_bad.sql failed", err)
    assert.is_false(db:is_applied("0001_bad.sql"))
    assert.is_false(db:exec("SELECT x FROM t;"))
  end)

  it("rejects a table with more than one row", function()
    local db = migrated()
    assert.is_true(db:exec("INSERT INTO digit VALUES (5, 5, 6, 0);"))
    local row, err = db:read()
    assert.is_nil(row)
    assert.matches("more than one row", err)
  end)
end)

describe("contract", function()
  it("answers GET /value and GET /next", function()
    local a = contract()
    assert.are.same(
      { status = 200, content_type = "application/json", body = '{"digit":4,"value":4}' },
      a:handle("GET", "/value")
    )
    assert.are.same(
      { status = 200, content_type = "application/json", body = '{"digit":4,"next":5,"carry":false}' },
      a:handle("GET", "/next")
    )
  end)

  it("answers from the database, not from constants", function()
    local a, db = contract()
    assert.is_true(db:exec("UPDATE digit SET next = 7, carry = 1;"))
    assert.are.equal('{"digit":4,"next":7,"carry":true}', a:handle("GET", "/next").body)
  end)

  it("reports health from the database", function()
    local a = contract()
    local reply = a:handle("GET", "/health")
    assert.are.equal(200, reply.status)
    assert.are.equal('{"status":"ok","checks":{"database":"ok"}}', reply.body)
  end)

  it("answers 503 and counts an error when the row cannot be read", function()
    local a, db, m = contract()
    assert.is_true(db:exec("DROP TABLE digit;"))
    local reply = a:handle("GET", "/next")
    assert.are.equal(503, reply.status)
    assert.are.equal("application/problem+json", reply.content_type)
    assert.are.equal(1, m:get("next", "error"))
    assert.are.equal(503, a:handle("GET", "/health").status)
  end)

  it("answers 503 when the database holds another digit", function()
    local db = migrated()
    local a = api.new(db, 3, metrics.new(3, "0.1.0"))
    assert.are.equal(503, a:handle("GET", "/value").status)
    assert.are.equal('{"status":"error","checks":{"database":"error"}}', a:handle("GET", "/health").body)
  end)

  it("answers 404 for an unknown path and 405 with Allow for another method", function()
    local a = contract()
    local missing = a:handle("GET", "/nope")
    assert.are.equal(404, missing.status)
    assert.are.equal(
      '{"type":"about:blank","title":"Not Found","status":404,"detail":"the digit service has no such path"}',
      missing.body
    )
    local wrong = a:handle("POST", "/next")
    assert.are.equal(405, wrong.status)
    assert.are.equal("GET", wrong.allow)
  end)

  it("exposes the counters as Prometheus text", function()
    local a = contract()
    a:handle("GET", "/next")
    local text = a:handle("GET", "/metrics").body
    assert.truthy(text:find('digit_requests_total{digit="4",endpoint="next",outcome="ok"} 1\n', 1, true))
    assert.truthy(text:find('digit_requests_total{digit="4",endpoint="value",outcome="error"} 0\n', 1, true))
    assert.truthy(text:find('digit_build_info{digit="4",version="0.1.0"} 1\n', 1, true))
  end)
end)

describe("trace and log", function()
  it("accepts a valid traceparent", function()
    local trace_id, span_id = trace.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
    assert.are.equal("4bf92f3577b34da6a3ce929d0e0e4736", trace_id)
    assert.are.equal("00f067aa0ba902b7", span_id)
  end)

  it("rejects invalid traceparents", function()
    for _, header in ipairs({
      "",
      "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
      "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
      "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01",
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-x",
    }) do
      assert.is_nil(trace.parse(header))
    end
    assert.is_nil(trace.parse(nil))
  end)

  it("escapes JSON strings and parses levels", function()
    assert.are.equal('a\\"b\\\\c\\n\\u0001', log.json_escape('a"b\\c\n\1'))
    assert.are.equal("debug", log.parse_level("debug", "info"))
    assert.are.equal("info", log.parse_level("loud", "info"))
    assert.are.same({ "debug", "info", "warn", "error" }, log.levels)
  end)
end)

describe("http", function()
  it("parses request lines and header fields", function()
    assert.are.same({ "GET", "/next?x=1", "1" }, { http.parse_request_line("GET /next?x=1 HTTP/1.1") })
    assert.is_nil(http.parse_request_line("GET /next HTTP/2.0"))
    assert.is_nil(http.parse_request_line("garbage"))
    assert.are.same({ "content-length", "5" }, { http.parse_header("Content-Length:  5 ") })
    assert.is_nil(http.parse_header(" folded"))
  end)

  it("keeps HTTP/1.1 connections unless asked to close", function()
    assert.is_true(http.keep_alive("1", {}))
    assert.is_false(http.keep_alive("1", { connection = "Close" }))
    assert.is_false(http.keep_alive("0", {}))
    assert.is_true(http.keep_alive("0", { connection = "keep-alive" }))
  end)

  it("serves pipelined requests on one connection", function()
    local out = serve("GET /value HTTP/1.1\r\nHost: x\r\n\r\nGET /next?x=1 HTTP/1.1\r\n\r\n")
    assert.are.same({ 200, 200 }, statuses(out))
    assert.truthy(out:find('{"digit":4,"value":4}', 1, true))
    assert.truthy(out:find('{"digit":4,"next":5,"carry":false}', 1, true))
    assert.is_nil(out:find("Connection: close", 1, true))
  end)

  it("skips request bodies before the next request", function()
    local out = serve(
      "POST /value HTTP/1.1\r\nContent-Length: 5\r\n\r\nhelloGET /next HTTP/1.1\r\n"
        .. "Transfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\nGET /value HTTP/1.1\r\n\r\n"
    )
    assert.are.same({ 405, 200, 200 }, statuses(out))
    assert.truthy(out:find("Allow: GET\r\n", 1, true))
  end)

  it("answers HEAD without a body and closes HTTP/1.0 connections", function()
    local out = serve("HEAD /next HTTP/1.0\r\n\r\nGET /value HTTP/1.1\r\n\r\n")
    assert.are.same({ 405 }, statuses(out))
    assert.truthy(out:find("Connection: close\r\n\r\n$"))
  end)

  it("rejects malformed and oversized requests and closes", function()
    assert.are.same({ 400 }, statuses(serve("garbage\r\n\r\nGET /value HTTP/1.1\r\n\r\n")))
    assert.are.same({ 400 }, statuses(serve("GET /value HTTP/1.1\r\nbad header\r\n\r\n")))
    assert.are.same({ 400 }, statuses(serve("GET /value HTTP/1.1\r\nContent-Length: x\r\n\r\n")))
    local big = string.format("POST /value HTTP/1.1\r\nContent-Length: %d\r\n\r\n", http.MAX_BODY + 1)
    assert.are.same({ 413 }, statuses(serve(big)))
    local long = "GET /value HTTP/1.1\r\nX: " .. string.rep("a", http.MAX_HEAD) .. "\r\n\r\n"
    local out = serve(long)
    assert.are.same({ 431 }, statuses(out))
    assert.truthy(out:find("application/problem+json", 1, true))
  end)

  it("ends quietly when the client closes between requests", function()
    assert.are.equal("", serve(""))
    assert.are.equal("", serve("\r\n"))
  end)
end)
