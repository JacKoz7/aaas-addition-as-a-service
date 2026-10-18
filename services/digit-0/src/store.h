/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/store.h
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         SQLite storage of the digit: opening the database,
 *                  applying the versioned migrations and reading the row
 *                  that holds the value and successor of the digit.
 * Related Docs:    services/digit-0/README.md, migrations/0001_digit.sql,
 *                  CLAUDE.md 4.4, ADR-0022
 */

/**
 * @file store.h
 * @brief SQLite storage of the digit (open, migrate, read).
 *
 * @details The digit service keeps its only fact, the value and successor
 * of its digit, in its own SQLite database (CLAUDE.md 4.4). Migrations are
 * the files `NNNN_*.sql` of the migrations directory, applied once each in
 * lexical order and recorded in the table `schema_migrations`.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#ifndef DIGIT_STORE_H
#define DIGIT_STORE_H

#include <sqlite3.h>
#include <stdbool.h>

/**
 * @brief The digit row of the database.
 *
 * @details Mirrors the table `digit` of migrations/0001_digit.sql.
 *
 * @par Business Justification
 * The one fact the service exists to serve.
 *
 * @par Thread Safety
 * Plain value; safe to copy.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @see store_read
 */
struct digit_row {
  int digit;  /**< The digit the service represents, 0..9. */
  int value;  /**< Numeric value of the digit, 0..9. */
  int next;   /**< Successor of the digit in base 10, 0..9. */
  bool carry; /**< True when the successor wraps to 0 (digit 9 only). */
};

/**
 * @brief Open (or create) the SQLite database file.
 *
 * @details Opens @p path read-write, creating it when missing, sets a busy
 * timeout of 2 s and enables foreign keys.
 *
 * @par Business Justification
 * Each service owns its database (CLAUDE.md 1, rule 4).
 *
 * @param path Database file path; `:memory:` for an in-memory database.
 * @param[out] db Receives the connection on success, NULL on failure.
 * @return 0 on success, -1 on failure.
 *
 * @par Errors
 * -1 when SQLite cannot open the file (missing directory, permissions).
 * @par Side Effects
 * Creates the file when missing.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Safe; the returned connection must be used by one thread at a time.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * sqlite3 *db;
 * if (store_open("/data/digit-0.db", &db) != 0) return 1;
 * @endcode
 * @see store_close
 */
int store_open(const char *path, sqlite3 **db);

/**
 * @brief Apply the migrations of a directory that are not applied yet.
 *
 * @details Creates `schema_migrations` when missing, lists the files of
 * @p dir whose names end in `.sql`, sorts them lexically and applies each
 * file whose name is not recorded yet, in one transaction per file together
 * with its record. Running it again applies nothing.
 *
 * @par Business Justification
 * Migrations run at start-up and are versioned (CLAUDE.md 6.1); the seed of
 * the digit is a migration, so the digit lives in the database, not the code.
 *
 * @param db Open connection.
 * @param dir Directory with the migration files.
 * @param[out] applied Receives the number of files applied by this call;
 *             may be NULL.
 * @return 0 on success, -1 on failure (the failing file is rolled back).
 *
 * @par Errors
 * -1 when the directory cannot be read, a file cannot be read, or its SQL
 * fails; the reason is logged.
 * @par Side Effects
 * Reads files; writes the database; logs every applied file.
 * @par Complexity
 * O(f log f + s) for f files of total size s.
 * @par Thread Safety
 * Not safe; call before serving requests.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * int applied;
 * store_migrate(db, "/app/migrations", &applied);
 * @endcode
 * @see store_read
 */
int store_migrate(sqlite3 *db, const char *dir, int *applied);

/**
 * @brief Read the digit row.
 *
 * @details Requires the table `digit` to hold exactly one row; zero rows or
 * more than one are an error, as is any SQLite failure.
 *
 * @par Business Justification
 * GET /value, GET /next and GET /health answer from this read on every
 * request (CLAUDE.md 4.4).
 *
 * @param db Open, migrated connection.
 * @param[out] out Receives the row on success; untouched on failure.
 * @return 0 on success, -1 on failure.
 *
 * @par Errors
 * -1 when the query fails or the table does not hold exactly one row.
 * @par Side Effects
 * One SELECT.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * As the connection: one thread at a time.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * struct digit_row row;
 * if (store_read(db, &row) == 0) printf("%d -> %d\n", row.digit, row.next);
 * @endcode
 * @see digit_row
 */
int store_read(sqlite3 *db, struct digit_row *out);

/**
 * @brief Close the database connection.
 *
 * @details Accepts NULL.
 *
 * @par Business Justification
 * Graceful shutdown (CLAUDE.md 6.1) leaves the database consistent.
 *
 * @param db Connection or NULL.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * Releases the connection.
 * @par Complexity
 * O(1).
 * @par Thread Safety
 * Not safe while another thread uses the connection.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * store_close(db);
 * @endcode
 * @see store_open
 */
void store_close(sqlite3 *db);

#endif /* DIGIT_STORE_H */
