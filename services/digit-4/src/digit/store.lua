-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          src/digit/store.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         SQLite storage of the digit: opening the database,
--                  applying the versioned migrations and reading the row
--                  that holds the value and successor of the digit.
-- Related Docs:    services/digit-4/README.md, migrations/0001_digit.sql,
--                  CLAUDE.md 4.4, ADR-0022

--- SQLite storage of the digit (open, migrate, read).
--
-- The digit service keeps its only fact, the value and successor of its
-- digit, in its own SQLite database (CLAUDE.md 4.4). Migrations are the
-- files NNNN_*.sql of the migrations directory, applied once each in
-- lexical order and recorded in the table schema_migrations.
--
-- Failures follow the Lua convention: nil (or false) and a message.
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @module digit.store

local sqlite3 = require("lsqlite3")
local dirent = require("posix.dirent")
local log = require("digit.log")

local M = {}

-- The class of this module, defined below its constructor.
local Store

--- Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1).
-- Owner: AEC. Since: digit-4 0.1.0.
local BUSY_TIMEOUT_MS = 2000

--- Bookkeeping table of the migration runner: one row per applied file,
-- version is the file name, applied_at the UTC time (ISO 8601).
-- Owner: AEC. Since: digit-4 0.1.0.
local MIGRATIONS_TABLE = "CREATE TABLE IF NOT EXISTS schema_migrations ("
  .. " version TEXT PRIMARY KEY NOT NULL, applied_at TEXT NOT NULL) STRICT;"

--- Open (or create) the SQLite database file.
--
-- Description: opens path read-write, creating it when missing, sets a
-- busy timeout of 2 s and enables foreign keys.
--
-- Business Justification: each service owns its database.
--
-- Errors: nil and the SQLite message when the file cannot be opened.
-- Side Effects: creates the file when missing. Complexity: O(1).
-- Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string path database file path; ":memory:" for an in-memory database
-- @treturn ?Store the open store, nil on failure
-- @treturn ?string the error message on failure
-- @usage local store, err = store.open("/data/digit-4.db")
-- @see Store:migrate
function M.open(path)
  local db, _, message = sqlite3.open(path)
  if db == nil then
    log.write("error", "cannot open the database", nil, nil, message)
    return nil, message
  end
  db:busy_timeout(BUSY_TIMEOUT_MS)
  local self = setmetatable({ db = db }, Store)
  local ok, err = self:exec("PRAGMA foreign_keys = ON;")
  if not ok then
    db:close()
    return nil, err
  end
  return self
end

--- The SQLite database of the service (one connection).
--
-- Business Justification: each service owns its database (CLAUDE.md 1,
-- rule 4).
--
-- Thread Safety: one connection used by the single OS thread of the
-- service; no call yields, so requests never interleave inside it.
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @type Store
Store = {}
Store.__index = Store

--- Close the connection.
--
-- Business Justification: SQLite releases its locks and journal.
--
-- Errors: none. Side Effects: closes the connection. Complexity: O(1).
-- Thread Safety: safe once no request uses the store. Owner: AEC.
-- Since: digit-4 0.1.0.
-- @usage store:close()
-- @see open
function Store:close()
  self.db:close()
end

--- Execute one or more SQL statements without results.
--
-- Description: used by the migration runner and by the unit tests.
--
-- Business Justification: one place where SQL errors become messages.
--
-- Errors: false and the SQLite message when a statement fails.
-- Side Effects: whatever the SQL does. Complexity: that of the statements.
-- Thread Safety: as the store. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string sql SQL text
-- @treturn boolean true on success
-- @treturn ?string the error message on failure
-- @usage store:exec("UPDATE digit SET next = 7;")
-- @see Store:migrate
function Store:exec(sql)
  if self.db:exec(sql) ~= sqlite3.OK then
    return false, self.db:errmsg()
  end
  return true
end

--- Whether a migration is recorded in schema_migrations.
--
-- Description: a failing query counts as "not applied", so that the
-- following apply fails loudly instead of skipping silently.
--
-- Business Justification: each migration runs exactly once.
--
-- Errors: none. Side Effects: one SELECT. Complexity: O(log m).
-- Thread Safety: as the store. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string version migration file name
-- @treturn boolean true when recorded
-- @usage store:is_applied("0001_digit.sql")
-- @see Store:migrate
function Store:is_applied(version)
  local stmt = self.db:prepare("SELECT 1 FROM schema_migrations WHERE version = ?;")
  if stmt == nil then
    return false
  end
  stmt:bind_values(version)
  local found = stmt:step() == sqlite3.ROW
  stmt:finalize()
  return found
end

--- Apply one migration file and record it, in one transaction.
--
-- Description: on any failure the transaction is rolled back.
--
-- Business Justification: a half-applied migration must never be recorded
-- as applied.
--
-- Errors: false and a message when the file cannot be read or its SQL or
-- the record fails. Side Effects: writes the database; logs the result.
-- Complexity: O(s) in the file size. Thread Safety: as the store.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string dir migrations directory
-- @tparam string version migration file name inside dir
-- @treturn boolean true when applied
-- @treturn ?string the error message on failure
-- @usage store:apply("/app/migrations", "0001_digit.sql")
-- @see Store:migrate
function Store:apply(dir, version)
  local file = io.open(dir .. "/" .. version, "rb")
  if file == nil then
    log.write("error", "cannot read migration", nil, nil, dir .. "/" .. version)
    return false, "cannot read migration " .. version
  end
  local sql = file:read("a")
  file:close()
  local ok, err = self:exec("BEGIN IMMEDIATE;")
  if ok then
    ok, err = self:exec(sql)
  end
  if ok then
    local stmt = self.db:prepare(
      "INSERT INTO schema_migrations (version, applied_at) VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));"
    )
    if stmt == nil then
      ok, err = false, self.db:errmsg()
    else
      stmt:bind_values(version)
      if stmt:step() ~= sqlite3.DONE then
        ok, err = false, self.db:errmsg()
      end
      stmt:finalize()
    end
  end
  if ok then
    ok, err = self:exec("COMMIT;")
  end
  if not ok then
    self.db:exec("ROLLBACK;")
    log.write("error", "migration failed", nil, nil, version .. ": " .. err)
    return false, "migration " .. version .. " failed: " .. err
  end
  log.write("info", "migration applied", nil, nil, version)
  return true
end

--- Apply the migrations of a directory that are not applied yet.
--
-- Description: creates schema_migrations when missing, lists the files
-- *.sql of dir that do not start with a dot, sorts them lexically and
-- applies each file not recorded yet, in one transaction per file with its
-- record. Running it again applies nothing.
--
-- Business Justification: migrations run at start-up and are versioned
-- (CLAUDE.md 6.1); the seed of the digit is a migration, so the digit lives
-- in the database, not the code.
--
-- Errors: nil and a message when the directory cannot be read or a file
-- fails. Side Effects: reads files; writes the database; logs each applied
-- file. Complexity: O(f log f + s). Thread Safety: call before serving.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string dir directory with the migration files
-- @treturn ?integer number of files applied by this call, nil on failure
-- @treturn ?string the error message on failure
-- @usage local applied, err = store:migrate("/app/migrations")
-- @see Store:read
function Store:migrate(dir)
  local ok, err = self:exec(MIGRATIONS_TABLE)
  if not ok then
    log.write("error", "cannot create schema_migrations", nil, nil, err)
    return nil, err
  end
  local listed, names = pcall(dirent.dir, dir)
  if not listed or names == nil then
    log.write("error", "cannot read the migrations directory", nil, nil, dir)
    return nil, "cannot read the migrations directory " .. dir
  end
  local files = {}
  for _, name in ipairs(names) do
    if name:sub(1, 1) ~= "." and #name > 4 and name:sub(-4) == ".sql" then
      files[#files + 1] = name
    end
  end
  table.sort(files)
  local applied = 0
  for _, name in ipairs(files) do
    if not self:is_applied(name) then
      ok, err = self:apply(dir, name)
      if not ok then
        return nil, err
      end
      applied = applied + 1
    end
  end
  return applied
end

--- Read the digit row.
--
-- Description: requires the table digit to hold exactly one row; zero rows
-- or more than one are an error, as is any SQLite failure.
--
-- Business Justification: GET /value, GET /next and GET /health answer
-- from this read on every request (CLAUDE.md 4.4).
--
-- Errors: nil and a message when the query fails or the table does not
-- hold exactly one row. Side Effects: one SELECT. Complexity: O(1).
-- Thread Safety: as the store. Owner: AEC. Since: digit-4 0.1.0.
-- @treturn ?table the row: digit, value and next (integers 0..9) and carry
--   (boolean); nil on failure
-- @treturn ?string the error message on failure
-- @usage local row, err = store:read()
-- @see Store:migrate
function Store:read()
  local stmt = self.db:prepare("SELECT digit, value, next, carry FROM digit LIMIT 2;")
  if stmt == nil then
    return nil, self.db:errmsg()
  end
  local row, err
  if stmt:step() ~= sqlite3.ROW then
    err = "the table digit holds no row"
  else
    local values = stmt:get_values()
    row = { digit = values[1], value = values[2], next = values[3], carry = values[4] ~= 0 }
    if stmt:step() ~= sqlite3.DONE then
      row, err = nil, "the table digit holds more than one row"
    end
  end
  stmt:finalize()
  return row, err
end

return M
