-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          src/main.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Entry point of the digit-4 service: configuration,
--                  start-up checks, the HTTP server and the SIGTERM
--                  handling.
-- Related Docs:    services/digit-4/README.md, CLAUDE.md 4.4 and 6.1,
--                  ADR-0022, ADR-0026

--- Entry point of the digit-4 service.
--
-- Reads the configuration from the environment (AAAS_BOOTSTRAP=env, the
-- only mode before P5.2), opens and migrates the database, checks that it
-- holds the configured digit, serves HTTP on AAAS_HTTP_PORT and stops on
-- SIGTERM or SIGINT. Exits with status 1 when any start-up check fails.
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @script main

local cqueues = require("cqueues")
local signal = require("cqueues.signal")
local api = require("digit.api")
local http = require("digit.http")
local log = require("digit.log")
local metrics = require("digit.metrics")
local store = require("digit.store")

--- Version of the service (SemVer, docs/CHANGELOG.md).
-- Owner: AEC. Since: digit-4 0.1.0.
local SERVICE_VERSION = "0.1.0"

--- An environment variable, or a fallback when it is unset or empty.
--
-- Business Justification: configuration comes only from the environment
-- until P5.2 (CLAUDE.md 6.1).
--
-- Errors: none. Side Effects: reads the environment. Complexity: O(1).
-- Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string name variable name
-- @tparam string fallback value used when unset or empty
-- @treturn string the value
-- @usage env_or("AAAS_DB_PATH", "/data/digit-4.db")
-- @see load_config
local function env_or(name, fallback)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

--- Parse a decimal integer within a range.
--
-- Business Justification: invalid configuration stops the start instead
-- of being guessed at.
--
-- Errors: nil when text is not a plain decimal integer in [min, max].
-- Side Effects: none. Complexity: O(n). Thread Safety: safe. Owner: AEC.
-- Since: digit-4 0.1.0.
-- @tparam string text decimal text
-- @tparam integer min smallest allowed value
-- @tparam integer max largest allowed value
-- @treturn ?integer the value, nil when invalid
-- @usage parse_int("8080", 1, 65535) --> 8080
-- @see load_config
local function parse_int(text, min, max)
  if not text:match("^%d+$") or #text > 9 then
    return nil
  end
  local value = tonumber(text)
  if value < min or value > max then
    return nil
  end
  return value
end

--- Read the configuration from the environment.
--
-- Description: AAAS_BOOTSTRAP must be env (platform arrives with P5.2);
-- AAAS_DIGIT must be 0..9 and AAAS_HTTP_PORT 1..65535. Each failure is
-- logged at error level.
--
-- Business Justification: no hard-coded hosts, ports or paths
-- (CLAUDE.md 6.1).
--
-- Errors: nil when a value is invalid. Side Effects: reads the
-- environment; logs failures. Complexity: O(1). Thread Safety: safe.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @treturn ?table digit, port, db_path and migrations_dir; nil on failure
-- @usage local config = load_config()
-- @see main
local function load_config()
  local bootstrap = env_or("AAAS_BOOTSTRAP", "env")
  if bootstrap ~= "env" then
    log.write("error", "unsupported AAAS_BOOTSTRAP; only env exists before P5.2", nil, nil, bootstrap)
    return nil
  end
  local digit = parse_int(env_or("AAAS_DIGIT", "4"), 0, 9)
  if digit == nil then
    log.write("error", "AAAS_DIGIT must be 0..9", nil, nil, os.getenv("AAAS_DIGIT"))
    return nil
  end
  local port = parse_int(env_or("AAAS_HTTP_PORT", "8080"), 1, 65535)
  if port == nil then
    log.write("error", "AAAS_HTTP_PORT must be 1..65535", nil, nil, os.getenv("AAAS_HTTP_PORT"))
    return nil
  end
  return {
    digit = digit,
    port = port,
    db_path = env_or("AAAS_DB_PATH", "/data/digit-4.db"),
    migrations_dir = env_or("AAAS_MIGRATIONS_DIR", "/app/migrations"),
  }
end

--- Run the service.
--
-- Description: configuration, database open and migration, digit check,
-- then the server on a cqueues controller until SIGTERM or SIGINT; the
-- signals are blocked and read from a signalfd by a coroutine.
--
-- Business Justification: the digit-4 process (CLAUDE.md 2, row 17).
--
-- Errors: returns 1 when a start-up check fails or the event loop fails.
-- Side Effects: opens the database and a socket; logs; serves HTTP.
-- Complexity: runs until stopped. Thread Safety: call once.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @treturn integer the exit status, 0 after a graceful stop
-- @usage os.exit(main())
-- @see load_config
local function main()
  log.init(env_or("AAAS_SERVICE", "digit-4"), log.parse_level(os.getenv("AAAS_LOG_LEVEL"), "info"))
  local config = load_config()
  if config == nil then
    return 1
  end
  local db = store.open(config.db_path)
  if db == nil then
    return 1
  end
  if db:migrate(config.migrations_dir) == nil then
    db:close()
    return 1
  end
  local row = db:read()
  if row == nil or row.digit ~= config.digit then
    log.write("error", "the database does not hold the configured digit", nil, nil, config.db_path)
    db:close()
    return 1
  end

  local contract = api.new(db, config.digit, metrics.new(config.digit, SERVICE_VERSION))
  local server, err = http.listen(config.port, function(method, path)
    return contract:handle(method, path)
  end)
  if server == nil then
    log.write("error", "cannot start the HTTP server", nil, nil, err)
    db:close()
    return 1
  end

  signal.block(signal.SIGTERM, signal.SIGINT)
  local signals = signal.listen(signal.SIGTERM, signal.SIGINT)
  local cq = cqueues.new()
  cq:wrap(function()
    local received = signals:wait()
    log.write("info", "shutting down", nil, nil, received == signal.SIGTERM and "SIGTERM" or "SIGINT")
    server:stop()
  end)
  cq:wrap(function()
    server:run(cq)
  end)
  log.write(
    "info",
    "listening",
    nil,
    nil,
    string.format("port %d, digit %d, version %s", config.port, config.digit, SERVICE_VERSION)
  )

  while not server.finished do
    local ok, loop_err = cq:step()
    if not ok then
      log.write("error", "event loop failed", nil, nil, tostring(loop_err))
      db:close()
      return 1
    end
  end
  db:close()
  log.write("info", "stopped")
  return 0
end

os.exit(main())
