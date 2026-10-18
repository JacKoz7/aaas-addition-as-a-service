-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          tools/doc-coverage.lua
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Documentation coverage gate of the Lua sources: every
--                  module, function, method, constant and module-level
--                  table must carry an LDoc comment (CLAUDE.md 6.5.4).
-- Related Docs:    services/digit-4/Dockerfile (doc-coverage stage),
--                  CLAUDE.md 6.5.3, ADR-0026

--- Documentation coverage gate of the Lua sources.
--
-- LDoc documents what carries a doc comment and silently skips what does
-- not, so it cannot prove coverage on its own. This script reads each file
-- given on the command line and requires an LDoc comment (a block of
-- comment lines whose first line starts with three dashes) directly above
-- every definition:
--
-- * every named function, local or not, at any depth;
-- * every module-level local constant (upper-case name) or table;
-- * every module field (M.name = ...);
-- * every class table (Name = {}), assigned to a local declared earlier
--   so that its constructor can precede it in the LDoc output.
--
-- It also requires one @module or @script tag per file. The module table
-- itself (local M = {}) is documented by that tag. It prints each missing
-- comment and exits with status 1 when any is missing.
--
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @script doc-coverage

--- Patterns of the lines that start a definition.
-- Owner: AEC. Since: digit-4 0.1.0.
-- @table DEFINITIONS
local DEFINITIONS = {
  "^%s*local%s+function%s+[%w_]+",
  "^%s*function%s+[%w_.:]+",
  "^local%s+%u[%u%d_]*%s*=",
  "^local%s+[%a_][%w_]*%s*=%s*{",
  "^M%.[%w_]+%s*=",
  "^%u[%w_]*%s*=%s*{",
}

--- Whether a line starts a definition that needs a comment.
--
-- Business Justification: the rule set of CLAUDE.md 6.5.3 for Lua.
--
-- Errors: none. Side Effects: none. Complexity: O(1) per line.
-- Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string line a source line
-- @treturn boolean true when the line needs a doc comment
-- @usage is_definition("local function f()") --> true
-- @see check
local function is_definition(line)
  if line:match("^local%s+M%s*=%s*{}%s*$") then
    return false
  end
  for _, pattern in ipairs(DEFINITIONS) do
    if line:match(pattern) then
      return true
    end
  end
  return false
end

--- Whether the comment block that ends at line index i is an LDoc comment.
--
-- Description: walks up over comment lines and requires the first line of
-- the block to start with three dashes.
--
-- Business Justification: a plain comment is not exported by LDoc.
--
-- Errors: none. Side Effects: none. Complexity: O(k) in the block length.
-- Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam table lines the file's lines
-- @tparam integer i index of the line above the definition
-- @treturn boolean true when an LDoc comment ends at i
-- @usage documented(lines, 41)
-- @see check
local function documented(lines, i)
  if i < 1 or not lines[i]:match("^%s*%-%-") then
    return false
  end
  while i > 1 and lines[i - 1]:match("^%s*%-%-") and not lines[i]:match("^%s*%-%-%-") do
    i = i - 1
  end
  return lines[i]:match("^%s*%-%-%-") ~= nil
end

--- Check one file and print its findings.
--
-- Business Justification: one finding per undocumented definition.
--
-- Errors: raises when the file cannot be read. Side Effects: reads the
-- file; prints findings. Complexity: O(n) in the file length.
-- Thread Safety: safe. Owner: AEC. Since: digit-4 0.1.0.
-- @tparam string path file path
-- @treturn integer number of definitions checked
-- @treturn integer number of findings
-- @usage local total, missing = check("src/main.lua")
-- @see is_definition
local function check(path)
  local lines = {}
  for line in assert(io.open(path)):lines() do
    lines[#lines + 1] = line
  end
  local total, missing, tagged = 0, 0, false
  for i, line in ipairs(lines) do
    if line:match("^%-%-%s*@module%s") or line:match("^%-%-%s*@script%s") then
      tagged = true
    end
    if is_definition(line) then
      total = total + 1
      if not documented(lines, i - 1) then
        missing = missing + 1
        print(string.format("%s:%d: undocumented: %s", path, i, line))
      end
    end
  end
  total = total + 1
  if not tagged then
    missing = missing + 1
    print(path .. ": no @module or @script comment")
  end
  return total, missing
end

local total, missing = 0, 0
for _, path in ipairs(arg) do
  local t, m = check(path)
  total, missing = total + t, missing + m
end
print(string.format("doc-coverage: %d/%d definitions documented", total - missing, total))
os.exit(missing == 0 and 0 or 1)
