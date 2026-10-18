-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       digit-1
-- Module:          migrations/0001_digit.sql
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Schema and seed of the digit-1 database: the one row that
--                  holds the value of digit 1 and its successor in base 10.
-- Related Docs:    services/digit-1/README.md, contracts/http/digit.yaml,
--                  CLAUDE.md 4.4, ADR-0022
--
-- SQLite has no COMMENT ON statement (CLAUDE.md 6.5.3); every table and
-- column is documented by the comment directly above it, which SQLite also
-- keeps in sqlite_schema.sql, so `.schema` shows the documentation.

-- digit: the digit this service represents. Exactly one row; the service
-- answers GET /value and GET /next from it (CLAUDE.md 4.4: never from
-- constants in the code) and refuses to start when the row is missing or
-- names another digit.
CREATE TABLE digit (
  -- The digit the service represents (primary key), 0..9.
  digit INTEGER PRIMARY KEY NOT NULL CHECK (digit BETWEEN 0 AND 9),
  -- Numeric value of the digit, 0..9; equal to `digit`.
  value INTEGER NOT NULL CHECK (value BETWEEN 0 AND 9),
  -- Successor of the digit in base 10, 0..9: (digit + 1) mod 10.
  next INTEGER NOT NULL CHECK (next BETWEEN 0 AND 9),
  -- 1 when the successor wraps to 0 and carries one to the next higher
  -- position (only digit 9), 0 otherwise.
  carry INTEGER NOT NULL CHECK (carry IN (0, 1))
) STRICT;

-- Seed: digit 1 has the value 1, the successor 2 and no carry.
INSERT INTO digit (digit, value, next, carry) VALUES (1, 1, 2, 0);
