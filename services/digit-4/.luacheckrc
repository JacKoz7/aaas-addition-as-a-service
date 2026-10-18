-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          .luacheckrc
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Configuration of luacheck, the Lua linter: Lua 5.4 standard
--                  library, line length, test globals.
-- Related Docs:    services/digit-4/docs/SERVICE_CHARTER.md

--- luacheck configuration.
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @script luacheckrc
std = "lua54"
max_line_length = 120
codes = true
files["tests/"] = { std = "+busted" }
files["config.ld"] = { globals = { "project", "title", "description", "file", "format", "all", "not_luadoc", "dir" } }
