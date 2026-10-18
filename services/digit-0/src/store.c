/*
 * SPDX-License-Identifier: MIT
 * Copyright (c) 2026 AaaS Contributors
 *
 * Component:       digit-0
 * Module:          src/store.c
 * Owning Team:     Arithmetic Excellence Center (AEC)
 * Classification:  INTERNAL
 * Purpose:         SQLite storage of the digit: open, migrate, read.
 * Related Docs:    src/store.h, migrations/0001_digit.sql, ADR-0022
 */

/**
 * @file store.c
 * @brief Implementation of store.h.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 */

#include "store.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "log.h"

/** @brief Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1). */
static const int BUSY_TIMEOUT_MS = 2000;

/**
 * @brief Bookkeeping table of the migration runner.
 *
 * @details One row per applied migration file: `version` is the file name,
 * `applied_at` the UTC time of application (ISO 8601). Created by the
 * runner itself, before any migration.
 */
static const char *const MIGRATIONS_TABLE = "CREATE TABLE IF NOT EXISTS schema_migrations ("
                                            " version TEXT PRIMARY KEY NOT NULL,"
                                            " applied_at TEXT NOT NULL"
                                            ") STRICT;";

int store_open(const char *path, sqlite3 **db) {
  *db = NULL;
  sqlite3 *conn = NULL;
  if (sqlite3_open_v2(path, &conn, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) != SQLITE_OK) {
    log_write(LVL_ERROR, "cannot open the database", NULL, NULL, sqlite3_errmsg(conn));
    sqlite3_close(conn);
    return -1;
  }
  sqlite3_busy_timeout(conn, BUSY_TIMEOUT_MS);
  sqlite3_exec(conn, "PRAGMA foreign_keys = ON;", NULL, NULL, NULL);
  *db = conn;
  return 0;
}

/**
 * @brief scandir filter: keep regular names ending in `.sql`.
 *
 * @details Hidden files (leading dot) are skipped.
 *
 * @par Business Justification
 * Only migration files are applied.
 *
 * @param entry Directory entry.
 * @return Non-zero to keep the entry.
 *
 * @par Errors
 * None.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the name length.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * scandir(dir, &names, is_sql_file, alphasort);
 * @endcode
 * @see store_migrate
 */
static int is_sql_file(const struct dirent *entry) {
  const char *name = entry->d_name;
  size_t len = strlen(name);
  return name[0] != '.' && len > 4 && strcmp(name + len - 4, ".sql") == 0;
}

/**
 * @brief Read a whole file into a NUL-terminated heap buffer.
 *
 * @details The caller frees the buffer.
 *
 * @par Business Justification
 * Migration files are executed as one SQL script each.
 *
 * @param path File path.
 * @return The content, or NULL on failure.
 *
 * @par Errors
 * NULL when the file cannot be opened or read, or memory is exhausted.
 * @par Side Effects
 * Reads the file; allocates memory.
 * @par Complexity
 * O(s) in the file size.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * char *sql = read_file("/app/migrations/0001_digit.sql");
 * free(sql);
 * @endcode
 * @see store_migrate
 */
static char *read_file(const char *path) {
  FILE *file = fopen(path, "rb");
  if (file == NULL) {
    return NULL;
  }
  char *buffer = NULL;
  if (fseek(file, 0, SEEK_END) == 0) {
    long size = ftell(file);
    if (size >= 0 && fseek(file, 0, SEEK_SET) == 0) {
      buffer = malloc((size_t)size + 1);
      if (buffer != NULL && fread(buffer, 1, (size_t)size, file) == (size_t)size) {
        buffer[size] = '\0';
      } else {
        free(buffer);
        buffer = NULL;
      }
    }
  }
  (void)fclose(file);
  return buffer;
}

/**
 * @brief Whether a migration is already recorded in `schema_migrations`.
 *
 * @details A failing query counts as "not applied", so that the following
 * apply fails loudly instead of skipping silently.
 *
 * @par Business Justification
 * Each migration runs exactly once.
 *
 * @param db Open connection.
 * @param version Migration file name.
 * @return true when recorded.
 *
 * @par Errors
 * None (see details).
 * @par Side Effects
 * One SELECT.
 * @par Complexity
 * O(log m) in the number of migrations.
 * @par Thread Safety
 * As the connection.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * if (!is_applied(db, "0001_digit.sql")) { ... }
 * @endcode
 * @see store_migrate
 */
static bool is_applied(sqlite3 *db, const char *version) {
  sqlite3_stmt *stmt = NULL;
  bool applied = false;
  if (sqlite3_prepare_v2(db, "SELECT 1 FROM schema_migrations WHERE version = ?1;", -1, &stmt, NULL) == SQLITE_OK) {
    sqlite3_bind_text(stmt, 1, version, -1, SQLITE_STATIC);
    applied = sqlite3_step(stmt) == SQLITE_ROW;
  }
  sqlite3_finalize(stmt);
  return applied;
}

/**
 * @brief Apply one migration file and record it, in one transaction.
 *
 * @details On any failure the transaction is rolled back and the SQLite
 * message is logged.
 *
 * @par Business Justification
 * A half-applied migration must never be recorded as applied.
 *
 * @param db Open connection.
 * @param dir Migrations directory.
 * @param version Migration file name inside @p dir.
 * @return 0 on success, -1 on failure.
 *
 * @par Errors
 * -1 when the file cannot be read or its SQL or the record fails.
 * @par Side Effects
 * Writes the database; logs the outcome.
 * @par Complexity
 * O(s) in the size of the file.
 * @par Thread Safety
 * As the connection.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-0 0.1.0
 * @par Example
 * @code
 * apply_file(db, "/app/migrations", "0001_digit.sql");
 * @endcode
 * @see store_migrate
 */
static int apply_file(sqlite3 *db, const char *dir, const char *version) {
  char path[4096];
  if (snprintf(path, sizeof path, "%s/%s", dir, version) >= (int)sizeof path) {
    log_write(LVL_ERROR, "migration path too long", NULL, NULL, version);
    return -1;
  }
  char *sql = read_file(path);
  if (sql == NULL) {
    log_write(LVL_ERROR, "cannot read migration", NULL, NULL, path);
    return -1;
  }
  char *error = NULL;
  int rc = sqlite3_exec(db, "BEGIN IMMEDIATE;", NULL, NULL, &error);
  if (rc == SQLITE_OK) {
    rc = sqlite3_exec(db, sql, NULL, NULL, &error);
  }
  if (rc == SQLITE_OK) {
    sqlite3_stmt *stmt = NULL;
    rc = sqlite3_prepare_v2(db,
                            "INSERT INTO schema_migrations (version, applied_at) "
                            "VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));",
                            -1, &stmt, NULL);
    if (rc == SQLITE_OK) {
      sqlite3_bind_text(stmt, 1, version, -1, SQLITE_STATIC);
      rc = sqlite3_step(stmt) == SQLITE_DONE ? SQLITE_OK : SQLITE_ERROR;
    }
    sqlite3_finalize(stmt);
  }
  if (rc == SQLITE_OK) {
    rc = sqlite3_exec(db, "COMMIT;", NULL, NULL, &error);
  }
  free(sql);
  if (rc != SQLITE_OK) {
    log_write(LVL_ERROR, "migration failed", NULL, NULL, error != NULL ? error : sqlite3_errmsg(db));
    sqlite3_free(error);
    sqlite3_exec(db, "ROLLBACK;", NULL, NULL, NULL);
    return -1;
  }
  log_write(LVL_INFO, "migration applied", NULL, NULL, version);
  return 0;
}

int store_migrate(sqlite3 *db, const char *dir, int *applied) {
  if (applied != NULL) {
    *applied = 0;
  }
  if (sqlite3_exec(db, MIGRATIONS_TABLE, NULL, NULL, NULL) != SQLITE_OK) {
    log_write(LVL_ERROR, "cannot create schema_migrations", NULL, NULL, sqlite3_errmsg(db));
    return -1;
  }
  struct dirent **names = NULL;
  int count = scandir(dir, &names, is_sql_file, alphasort);
  if (count < 0) {
    log_write(LVL_ERROR, "cannot read the migrations directory", NULL, NULL, dir);
    return -1;
  }
  int status = 0;
  for (int i = 0; i < count; i++) {
    if (status == 0 && !is_applied(db, names[i]->d_name)) {
      status = apply_file(db, dir, names[i]->d_name);
      if (status == 0 && applied != NULL) {
        (*applied)++;
      }
    }
    free(names[i]);
  }
  free((void *)names);
  return status;
}

int store_read(sqlite3 *db, struct digit_row *out) {
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(db, "SELECT digit, value, next, carry FROM digit LIMIT 2;", -1, &stmt, NULL) != SQLITE_OK) {
    sqlite3_finalize(stmt);
    return -1;
  }
  int status = -1;
  if (sqlite3_step(stmt) == SQLITE_ROW) {
    struct digit_row row = {
        .digit = sqlite3_column_int(stmt, 0),
        .value = sqlite3_column_int(stmt, 1),
        .next = sqlite3_column_int(stmt, 2),
        .carry = sqlite3_column_int(stmt, 3) != 0,
    };
    if (sqlite3_step(stmt) == SQLITE_DONE) {
      *out = row;
      status = 0;
    }
  }
  sqlite3_finalize(stmt);
  return status;
}

void store_close(sqlite3 *db) { sqlite3_close(db); }
