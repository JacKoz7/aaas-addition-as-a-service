-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          src/digit/http.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Minimal HTTP/1.1 server on cqueues: one coroutine per
--                  connection, persistent connections, bounded request
--                  heads and bodies, graceful stop.
-- Related Docs:    services/digit-4/README.md, contracts/http/digit.yaml,
--                  ADR-0026

--- HTTP/1.1 server of the digit service (RFC 9112), written in Lua on the
-- cqueues event loop.
--
-- No HTTP server library is packaged for Lua 5.4 on Alpine (lua-http is
-- packaged up to Lua 5.3), so the service reads and writes HTTP/1.1 itself
-- (ADR-0026). It serves what the digit contract needs: a request line,
-- header fields, a body that is read and discarded (Content-Length or
-- chunked), persistent connections, HEAD without a body and problem
-- details for malformed requests.
--
-- Every connection runs in its own coroutine; a slow or idle client only
-- holds its own coroutine. The functions that do not touch a socket are
-- exported for the unit tests.
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @module digit.http

local cqueues = require("cqueues")
local errno = require("cqueues.errno")
local socket = require("cqueues.socket")
local api = require("digit.api")
local log = require("digit.log")
local trace = require("digit.trace")

local M = {}

-- The class of this module, defined below its constructor.
local Server

--- Largest request head (request line and header fields), in bytes; a
-- larger head is answered 431.
-- Owner: AEC. Since: digit-4 0.1.0.
M.MAX_HEAD = 8192

--- Largest request body read and discarded, in bytes; a larger one is
-- answered 413 without being read.
-- Owner: AEC. Since: digit-4 0.1.0.
M.MAX_BODY = 65536

--- Seconds a connection may stay silent, between requests or within one,
-- before it is closed.
-- Owner: AEC. Since: digit-4 0.1.0.
M.IDLE_TIMEOUT = 10

--- Most connections served at once; further ones are closed on accept.
-- Owner: AEC. Since: digit-4 0.1.0.
M.MAX_CONNECTIONS = 256

--- Seconds between two checks of the stop flag by the accept loop.
-- Owner: AEC. Since: digit-4 0.1.0.
local ACCEPT_POLL = 0.2

--- Seconds the server waits for running requests after a stop.
-- Owner: AEC. Since: digit-4 0.1.0.
local DRAIN_TIMEOUT = 5

--- Seconds unread input is still read and discarded after the last reply,
-- before the socket is closed.
-- Owner: AEC. Since: digit-4 0.1.0.
local LINGER_TIMEOUT = 0.2

--- Most bytes read and discarded after the last reply.
-- Owner: AEC. Since: digit-4 0.1.0.
local LINGER_BYTES = 1048576

--- Reason phrases of the statuses the service sends.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @table REASONS
local REASONS = {
  [200] = "OK",
  [400] = "Bad Request",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [413] = "Content Too Large",
  [431] = "Request Header Fields Too Large",
  [503] = "Service Unavailable",
}

--- Parse a request line.
--
-- Description: the line must be method SP request-target SP HTTP-version,
-- where the method is a token (RFC 9110 tchar), the target has no spaces
-- or control characters and the version is HTTP/1.0 or HTTP/1.1. The
-- trailing CR LF must already be removed.
--
-- Business Justification: a malformed request is answered 400 instead of
-- being guessed at.
--
-- Errors: nil for an invalid line. Side Effects: none. Complexity: O(n).
-- Thread Safety: safe (pure). Owner: Arithmetic Excellence Center (AEC).
-- Since: digit-4 0.1.0.
-- @tparam string line request line without CR LF
-- @treturn ?string method, nil when invalid
-- @treturn ?string request target
-- @treturn ?string minor version, "0" or "1"
-- @usage http.parse_request_line("GET /next HTTP/1.1") --> "GET", "/next", "1"
-- @see parse_header
function M.parse_request_line(line)
  local method, target, minor = line:match("^([%w!#$%%&'*+%-.^_`|~]+) ([^%s%c]+) HTTP/1%.([01])$")
  return method, target, minor
end

--- Parse a header field line.
--
-- Description: name ":" OWS value OWS; the name is a token and is returned
-- in lower case. Obsolete line folding (a line starting with a space) is
-- rejected.
--
-- Business Justification: header fields decide the body length, the
-- persistence of the connection and the trace context.
--
-- Errors: nil for an invalid line. Side Effects: none. Complexity: O(n).
-- Thread Safety: safe (pure). Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string line header line without CR LF
-- @treturn ?string field name in lower case, nil when invalid
-- @treturn ?string field value without surrounding whitespace
-- @usage http.parse_header("Content-Length: 5") --> "content-length", "5"
-- @see parse_request_line
function M.parse_header(line)
  local name, value = line:match("^([%w!#$%%&'*+%-.^_`|~]+):[ \t]*(.-)[ \t]*$")
  if name == nil then
    return nil, nil
  end
  return name:lower(), value
end

--- Whether a comma-separated header value contains a token.
--
-- Business Justification: Connection: close and Transfer-Encoding: chunked
-- may come with other tokens.
--
-- Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam ?string value header value, nil when absent
-- @tparam string token lower-case token
-- @treturn boolean true when present (case-insensitive)
-- @usage has_token("keep-alive, Close", "close") --> true
-- @see keep_alive
local function has_token(value, token)
  if value == nil then
    return false
  end
  for item in value:lower():gmatch("[^,%s]+") do
    if item == token then
      return true
    end
  end
  return false
end

--- Whether the connection stays open after the reply.
--
-- Description: HTTP/1.1 keeps it unless the request says Connection:
-- close; HTTP/1.0 keeps it only with Connection: keep-alive.
--
-- Business Justification: callers reuse connections, which saves a TCP
-- handshake per digit call.
--
-- Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string minor minor HTTP version, "0" or "1"
-- @tparam table headers header fields by lower-case name
-- @treturn boolean true to keep the connection
-- @usage http.keep_alive("1", {}) --> true
-- @see serve_connection
function M.keep_alive(minor, headers)
  if minor == "1" then
    return not has_token(headers.connection, "close")
  end
  return has_token(headers.connection, "keep-alive")
end

--- Serialise a reply.
--
-- Description: status line, Date, Content-Type, Content-Length, Allow when
-- the reply has one and Connection: close when the connection ends; the
-- body is left out for HEAD.
--
-- Business Justification: one place produces the bytes of every answer.
--
-- Errors: none. Side Effects: reads the clock. Complexity: O(n) in the
-- body. Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table reply status, content_type, optional allow and body
-- @tparam boolean head true for a HEAD request
-- @tparam boolean close true when the connection is closed after the reply
-- @treturn string the response bytes
-- @usage http.format_reply({status = 200, content_type = "application/json", body = "{}"}, false, false)
-- @see digit.api
function M.format_reply(reply, head, close)
  local parts = {
    string.format("HTTP/1.1 %d %s\r\n", reply.status, REASONS[reply.status] or ""),
    os.date("!Date: %a, %d %b %Y %H:%M:%S GMT\r\n"),
    "Content-Type: " .. reply.content_type .. "\r\n",
    "Content-Length: " .. #reply.body .. "\r\n",
  }
  if reply.allow ~= nil then
    parts[#parts + 1] = "Allow: " .. reply.allow .. "\r\n"
  end
  if close then
    parts[#parts + 1] = "Connection: close\r\n"
  end
  parts[#parts + 1] = "\r\n"
  if not head then
    parts[#parts + 1] = reply.body
  end
  return table.concat(parts)
end

--- Read one line of the head.
--
-- Description: lines end with LF, optionally preceded by CR, which is
-- removed. budget is the number of head bytes still allowed.
--
-- Business Justification: bounds the memory a client can make the service
-- hold.
--
-- Errors: nil and "closed" at end of input or on a read error or timeout;
-- nil and "too large" when the line exceeds the budget. Side Effects:
-- reads from the connection. Complexity: O(n). Thread Safety: one
-- coroutine per connection. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table con the connection (cqueues socket or a test double)
-- @tparam integer budget head bytes still allowed
-- @treturn ?string the line without CR LF
-- @treturn string|integer the error, or the bytes consumed
-- @usage local line, used = read_line(con, 8192)
-- @see read_head
local function read_line(con, budget)
  local line = con:read("*L")
  if line == nil then
    return nil, "closed"
  end
  if #line > budget then
    return nil, "too large"
  end
  if line:sub(-1) ~= "\n" then
    return nil, "closed"
  end
  return (line:gsub("\r?\n$", "")), #line
end

--- Read a request head.
--
-- Description: skips empty lines before the request line (RFC 9112,
-- 2.2), then reads header fields up to the empty line. Repeated fields
-- are joined with a comma.
--
-- Business Justification: the first stage of every request.
--
-- Errors: nil and nil when the client closed or went silent before the
-- request line was complete; nil and 400 for a malformed head or one cut
-- short after the request line; nil and 431 for a head above MAX_HEAD. Side Effects: reads from the connection.
-- Complexity: O(n). Thread Safety: one coroutine per connection.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table con the connection
-- @treturn ?table the request: method, target, minor and headers
-- @treturn ?integer the error status, nil for a clean end
-- @usage local request, status = read_head(con)
-- @see read_body
local function read_head(con)
  local budget = M.MAX_HEAD
  local line, used
  repeat
    line, used = read_line(con, budget)
    if line == nil then
      return nil, used == "too large" and 431 or nil
    end
    budget = budget - used
  until line ~= ""
  local method, target, minor = M.parse_request_line(line)
  if method == nil then
    return nil, 400
  end
  local headers = {}
  while true do
    line, used = read_line(con, budget)
    if line == nil then
      return nil, used == "too large" and 431 or 400
    end
    budget = budget - used
    if line == "" then
      break
    end
    local name, value = M.parse_header(line)
    if name == nil then
      return nil, 400
    end
    headers[name] = headers[name] and headers[name] .. ", " .. value or value
  end
  return { method = method, target = target, minor = minor, headers = headers }
end

--- Read and discard n bytes of body.
--
-- Business Justification: the next request on the connection starts after
-- the body.
--
-- Errors: false when the input ends early. Side Effects: reads from the
-- connection. Complexity: O(n) time, O(1) memory per 4 KiB chunk.
-- Thread Safety: one coroutine per connection. Owner: AEC.
-- Since: digit-4 0.1.0.
-- @tparam table con the connection
-- @tparam integer n bytes to skip
-- @treturn boolean true when all bytes were read
-- @usage skip(con, 10)
-- @see read_body
local function skip(con, n)
  while n > 0 do
    local chunk = con:read(math.min(n, 4096))
    if chunk == nil or #chunk == 0 then
      return false
    end
    n = n - #chunk
  end
  return true
end

--- Read and discard the request body.
--
-- Description: Content-Length bodies up to MAX_BODY are skipped; chunked
-- bodies are skipped chunk by chunk with the same total limit (trailer
-- fields are read and ignored). A request with both Content-Length and
-- Transfer-Encoding, another transfer coding or an invalid length is
-- malformed (RFC 9112, 6.1 and 6.3).
--
-- Business Justification: the contract has no request bodies, but a body
-- sent anyway must not be mistaken for the next request.
--
-- Errors: 400 for a malformed or truncated body, 413 for one above
-- MAX_BODY. Side Effects: reads from the connection. Complexity: O(n).
-- Thread Safety: one coroutine per connection. Owner: AEC.
-- Since: digit-4 0.1.0.
-- @tparam table con the connection
-- @tparam table headers header fields by lower-case name
-- @treturn ?integer the error status, nil when the body was skipped
-- @usage local status = read_body(con, request.headers)
-- @see read_head
local function read_body(con, headers)
  local length, coding = headers["content-length"], headers["transfer-encoding"]
  if coding ~= nil then
    if length ~= nil or coding:lower() ~= "chunked" then
      return 400
    end
    local total = 0
    while true do
      local line = read_line(con, M.MAX_HEAD)
      local size = line and line:match("^(%x+)[ \t]*;?.*$")
      if size == nil or #size > 8 then
        return 400
      end
      size = tonumber(size, 16)
      total = total + size
      if total > M.MAX_BODY then
        return 413
      end
      if size == 0 then
        break
      end
      if not skip(con, size) or read_line(con, 2) ~= "" then
        return 400
      end
    end
    repeat
      local trailer = read_line(con, M.MAX_HEAD)
      if trailer == nil then
        return 400
      end
    until trailer == ""
    return nil
  end
  if length == nil then
    return nil
  end
  if not length:match("^%d+$") or #length > 9 then
    return 400
  end
  if tonumber(length) > M.MAX_BODY then
    return 413
  end
  return not skip(con, tonumber(length)) and 400 or nil
end

--- Send a reply and flush it.
--
-- Business Justification: the response leaves in one write, so no small
-- segment waits for a delayed acknowledgement.
--
-- Errors: false when the write fails (the client went away). Side Effects:
-- writes to the connection. Complexity: O(n). Thread Safety: one coroutine
-- per connection. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table con the connection
-- @tparam string bytes the serialised reply
-- @treturn boolean true when sent
-- @usage send(con, http.format_reply(reply, false, true))
-- @see format_reply
local function send(con, bytes)
  return con:write(bytes) ~= nil and con:flush() ~= nil
end

--- Error handler of every socket: return the error code instead of
-- raising.
--
-- Description: the default handler of cqueues raises on most errors (for
-- example a port in use or a connection reset), which would end the
-- coroutine or the process; with this handler the call returns nil and
-- the errno, which the callers treat as the end of the connection.
--
-- Business Justification: one misbehaving client must not stop the
-- service, and a start-up failure must be a JSON log line.
--
-- Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table _ the socket
-- @tparam string _ the operation
-- @tparam integer code the errno
-- @treturn integer code
-- @usage con:onerror(return_code)
-- @see Server:serve
local function return_code(_, _, code)
  return code
end

--- Serve the requests of one connection until it ends.
--
-- Description: reads a head, skips the body, asks handler for the reply,
-- logs it at debug level with the trace context and sends it; repeats
-- while the connection is persistent and stopping() is false. Malformed
-- requests are answered 400, 413 or 431 with problem details and close the
-- connection. busy(true) and busy(false) bracket each request.
--
-- Business Justification: the transport of the digit contract.
--
-- Errors: none (I/O errors close the connection). Side Effects: reads and
-- writes the connection; calls handler; logs. Complexity: O(n) per
-- request. Thread Safety: one coroutine per connection; handler must not
-- yield. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table con the connection (closed by the caller)
-- @tparam function handler function(method, path) returning a reply
-- @tparam function stopping returns true once the server stops
-- @tparam function busy called with true when a request starts and false
--   when it is answered
-- @usage http.serve_connection(con, function(m, p) return a:handle(m, p) end, stop, mark)
-- @see digit.api
function M.serve_connection(con, handler, stopping, busy)
  repeat
    local request, status = read_head(con)
    if request == nil then
      if status ~= nil then
        send(
          con,
          M.format_reply(api.problem(status, REASONS[status], "the request is malformed or too large"), false, true)
        )
        log.write("debug", "request rejected", nil, nil, tostring(status))
      end
      return
    end
    busy(true)
    status = read_body(con, request.headers)
    if status ~= nil then
      send(
        con,
        M.format_reply(api.problem(status, REASONS[status], "the request body is malformed or too large"), false, true)
      )
      log.write("debug", "request rejected", nil, nil, tostring(status))
      return
    end
    local path = request.target:match("^[^?]*")
    local reply = handler(request.method, path)
    local keep = M.keep_alive(request.minor, request.headers) and not stopping()
    local trace_id, span_id = trace.parse(request.headers.traceparent)
    log.write(
      "debug",
      "request answered",
      trace_id,
      span_id,
      string.format("%s %s -> %d", request.method, path, reply.status)
    )
    local sent = send(con, M.format_reply(reply, request.method == "HEAD", not keep))
    busy(false)
  until not (sent and keep)
end

--- Bind a listening socket.
--
-- Description: listens on all IPv4 addresses with SO_REUSEADDR; the bind
-- happens here, so a port in use fails the start.
--
-- Business Justification: port 8080 of every service (CLAUDE.md 6.1).
--
-- Errors: nil and a message when the port cannot be bound (for example
-- in use). Side Effects: opens a socket. Complexity: O(1). Thread Safety: call once.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam integer port TCP port, 1..65535
-- @tparam function handler function(method, path) returning a reply
-- @treturn ?Server the server, nil on failure
-- @treturn ?string the error message on failure
-- @usage local server, err = http.listen(8080, handler)
-- @see Server:run
function M.listen(port, handler)
  local listener = socket.listen({ host = "0.0.0.0", port = port, reuseaddr = true, nodelay = true })
  listener:onerror(return_code)
  local ok, err = listener:listen()
  if not ok then
    listener:close()
    return nil, string.format("cannot listen on port %d: %s", port, errno.strerror(err))
  end
  return setmetatable({
    listener = listener,
    handler = handler,
    stopped = false,
    finished = false,
    connections = {},
    count = 0,
  }, Server)
end

--- An HTTP server bound to a port.
--
-- Business Justification: the listener of the digit service.
--
-- Thread Safety: used by the coroutines of one cqueues controller.
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @type Server
Server = {}
Server.__index = Server

--- Serve one accepted connection in the current coroutine.
--
-- Description: tracks the connection until it ends, then closes it. The
-- close lingers: the write side is shut down first and input still
-- arriving is read and discarded for up to LINGER_TIMEOUT seconds, because
-- closing a socket with unread input makes the kernel send a reset that
-- can destroy the last reply (a 400, 413 or 431) before the client reads
-- it. Lines are capped at MAX_HEAD + 1 bytes, so a longer line reaches
-- read_head as an oversized fragment.
--
-- Business Justification: the stop can wake idle connections and wait for
-- busy ones.
--
-- Errors: none. Side Effects: socket I/O; changes the connection table.
-- Complexity: that of the requests. Thread Safety: coroutine of the
-- server's controller. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table con the accepted socket
-- @usage cq:wrap(function() self:serve(con) end)
-- @see serve_connection
function Server:serve(con)
  self.connections[con] = false
  self.count = self.count + 1
  con:onerror(return_code)
  con:setmode("b", "bf")
  con:setmaxline(M.MAX_HEAD + 1)
  con:settimeout(M.IDLE_TIMEOUT)
  pcall(M.serve_connection, con, self.handler, function()
    return self.stopped
  end, function(state)
    self.connections[con] = state
  end)
  self.connections[con] = nil
  con:shutdown("w")
  con:settimeout(LINGER_TIMEOUT)
  local deadline, discarded = cqueues.monotime() + LINGER_TIMEOUT, 0
  repeat
    local chunk = con:read(-4096)
    discarded = discarded + (chunk and #chunk or 0)
  until chunk == nil or discarded > LINGER_BYTES or cqueues.monotime() >= deadline
  self.count = self.count - 1
  con:close()
end

--- Accept and serve connections until stop is called, then drain.
--
-- Description: accepts with a 200 ms timeout so that the stop flag is
-- seen; each connection gets a coroutine on cq. Above MAX_CONNECTIONS a
-- new connection is closed at once. A failed accept (for example too many
-- open files) is logged and retried after 200 ms. After stop the listener is closed,
-- idle connections are shut down and busy ones get DRAIN_TIMEOUT seconds
-- to answer; then finished is set.
--
-- Business Justification: graceful shutdown in at most 10 s
-- (CLAUDE.md 6.1).
--
-- Errors: none. Side Effects: accepts connections; logs. Complexity: O(1)
-- per connection. Thread Safety: runs as a coroutine of cq.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table cq the cqueues controller
-- @usage cq:wrap(function() server:run(cq) end)
-- @see Server:stop
function Server:run(cq)
  while not self.stopped do
    local con, err = self.listener:accept(ACCEPT_POLL)
    if con == nil and err ~= errno.ETIMEDOUT then
      log.write("warn", "accept failed", nil, nil, errno.strerror(err))
      cqueues.sleep(ACCEPT_POLL)
    elseif con ~= nil then
      if self.count >= M.MAX_CONNECTIONS then
        log.write("warn", "connection limit reached; connection closed", nil, nil, tostring(M.MAX_CONNECTIONS))
        con:close()
      else
        cq:wrap(function()
          self:serve(con)
        end)
      end
    end
  end
  self.listener:close()
  for con, busy in pairs(self.connections) do
    if not busy then
      con:shutdown("r")
    end
  end
  local deadline = cqueues.monotime() + DRAIN_TIMEOUT
  while self.count > 0 and cqueues.monotime() < deadline do
    cqueues.sleep(0.05)
  end
  self.finished = true
end

--- Ask the server to stop.
--
-- Description: the accept loop sees the flag within 200 ms; running
-- requests are answered with Connection: close.
--
-- Business Justification: SIGTERM ends the service gracefully.
--
-- Errors: none. Side Effects: sets the stop flag. Complexity: O(1).
-- Thread Safety: coroutine of the server's controller. Owner: AEC.
-- Since: digit-4 0.1.0.
-- @usage server:stop()
-- @see Server:run
function Server:stop()
  self.stopped = true
end

return M
