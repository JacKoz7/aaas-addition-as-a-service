-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-4
-- Module:          config.ld
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Configuration of LDoc: sources, project title and output of
--                  the API documentation.
-- Related Docs:    services/digit-4/docs/SERVICE_CHARTER.md

--- LDoc configuration (read with ldoc -c config.ld).
-- Owner: Arithmetic Excellence Center (AEC). Since: digit-4 0.1.0.
-- @script config
project = "digit-4"
title = "digit-4 0.1.0"
description = "AaaS digit-4 service (Lua): authoritative source for the value and successor of digit 4."
file = { "src", "tests/digit_spec.lua", "tools" }
format = "plain"
all = true
not_luadoc = true
dir = "/api-docs"
