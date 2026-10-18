// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/store.cpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         SQLite storage of the digit: open, migrate, read.
// Related Docs:    src/store.hpp, migrations/0001_digit.sql, ADR-0022

/**
 * @file store.cpp
 * @brief Implementation of store.hpp.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#include "store.hpp"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <sstream>
#include <system_error>
#include <vector>

#include "log.hpp"

namespace aaas::digit {

namespace {

/// @brief Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1).
constexpr int busy_timeout_ms = 2000;

/**
 * @brief Bookkeeping table of the migration runner.
 *
 * @details One row per applied migration file: `version` is the file name,
 * `applied_at` the UTC time of application (ISO 8601). Created by the
 * runner itself, before any migration.
 */
constexpr const char *migrations_table = "CREATE TABLE IF NOT EXISTS schema_migrations ("
                                         " version TEXT PRIMARY KEY NOT NULL,"
                                         " applied_at TEXT NOT NULL"
                                         ") STRICT;";

/**
 * @brief Finalizes a prepared statement (deleter of Statement).
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */
struct Finalizer {
  /// @brief Finalize the statement.
  /// @param stmt Statement; may be null.
  void operator()(sqlite3_stmt *stmt) const noexcept { sqlite3_finalize(stmt); }
};

/// @brief A prepared statement that is finalized when it goes out of scope.
using Statement = std::unique_ptr<sqlite3_stmt, Finalizer>;

/**
 * @brief Prepare one SQL statement.
 *
 * @details Wraps sqlite3_prepare_v2.
 *
 * @par Business Justification
 * Statements are never leaked, even when an exception is thrown.
 *
 * @param db Connection.
 * @param sql One SQL statement.
 * @return The prepared statement.
 *
 * @par Errors
 * StoreError with the SQLite message when preparation fails.
 * @par Side Effects
 * None.
 * @par Complexity
 * O(n) in the SQL length.
 * @par Thread Safety
 * As the connection.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * Statement stmt = prepare(db, "SELECT 1;");
 * @endcode
 * @see Store::read
 */
Statement prepare(sqlite3 *db, const char *sql) {
  sqlite3_stmt *raw = nullptr;
  if (sqlite3_prepare_v2(db, sql, -1, &raw, nullptr) != SQLITE_OK) {
    sqlite3_finalize(raw);
    throw StoreError(sqlite3_errmsg(db));
  }
  return Statement(raw);
}

/**
 * @brief Read a whole file into a string.
 *
 * @details Binary read; the content is returned unchanged.
 *
 * @par Business Justification
 * Migration files are executed as one SQL script each.
 *
 * @param file File path.
 * @return The content.
 *
 * @par Errors
 * StoreError when the file cannot be opened or read.
 * @par Side Effects
 * Reads the file.
 * @par Complexity
 * O(s) in the file size.
 * @par Thread Safety
 * Safe.
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @par Example
 * @code
 * std::string sql = read_file("/app/migrations/0001_digit.sql");
 * @endcode
 * @see Store::migrate
 */
std::string read_file(const std::filesystem::path &file) {
  const std::ifstream in(file, std::ios::binary);
  std::ostringstream content;
  if (!in || !(content << in.rdbuf())) {
    throw StoreError("cannot read migration " + file.string());
  }
  return content.str();
}

} // namespace

Store::Store(const std::string &path) {
  sqlite3 *raw = nullptr;
  const int rc = sqlite3_open_v2(path.c_str(), &raw, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr);
  db_.reset(raw);
  if (rc != SQLITE_OK) {
    throw StoreError(std::string("cannot open the database: ") + sqlite3_errmsg(raw));
  }
  sqlite3_busy_timeout(db_.get(), busy_timeout_ms);
  execute("PRAGMA foreign_keys = ON;");
}

void Store::execute(const std::string &sql) {
  char *error = nullptr;
  if (sqlite3_exec(db_.get(), sql.c_str(), nullptr, nullptr, &error) != SQLITE_OK) {
    const std::string message = error != nullptr ? error : sqlite3_errmsg(db_.get());
    sqlite3_free(error);
    throw StoreError(message);
  }
}

bool Store::is_applied(const std::string &version) const {
  try {
    const Statement stmt = prepare(db_.get(), "SELECT 1 FROM schema_migrations WHERE version = ?1;");
    sqlite3_bind_text(stmt.get(), 1, version.c_str(), -1, SQLITE_TRANSIENT);
    return sqlite3_step(stmt.get()) == SQLITE_ROW;
  } catch (const StoreError &) {
    return false;
  }
}

void Store::apply(const std::filesystem::path &file) {
  const std::string sql = read_file(file);
  const std::string version = file.filename().string();
  execute("BEGIN IMMEDIATE;");
  try {
    execute(sql);
    const Statement stmt = prepare(db_.get(), "INSERT INTO schema_migrations (version, applied_at) "
                                              "VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));");
    sqlite3_bind_text(stmt.get(), 1, version.c_str(), -1, SQLITE_TRANSIENT);
    if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
      throw StoreError(sqlite3_errmsg(db_.get()));
    }
    execute("COMMIT;");
  } catch (const StoreError &error) {
    sqlite3_exec(db_.get(), "ROLLBACK;", nullptr, nullptr, nullptr);
    throw StoreError("migration " + version + " failed: " + error.what());
  }
  logging::write(logging::Level::info, "migration applied", std::nullopt, version);
}

int Store::migrate(const std::filesystem::path &dir) {
  execute(migrations_table);
  std::error_code ec;
  std::vector<std::filesystem::path> files;
  for (const auto &entry : std::filesystem::directory_iterator(dir, ec)) {
    const std::string name = entry.path().filename().string();
    if (entry.is_regular_file() && !name.starts_with('.') && name.size() > 4 && name.ends_with(".sql")) {
      files.push_back(entry.path());
    }
  }
  if (ec) {
    throw StoreError("cannot read the migrations directory " + dir.string() + ": " + ec.message());
  }
  std::ranges::sort(files, [](const auto &a, const auto &b) { return a.filename() < b.filename(); });
  int applied = 0;
  for (const auto &file : files) {
    if (!is_applied(file.filename().string())) {
      apply(file);
      ++applied;
    }
  }
  return applied;
}

DigitRow Store::read() const {
  const Statement stmt = prepare(db_.get(), "SELECT digit, value, next, carry FROM digit LIMIT 2;");
  if (sqlite3_step(stmt.get()) != SQLITE_ROW) {
    throw StoreError("the table digit holds no row");
  }
  const DigitRow row{
      .digit = sqlite3_column_int(stmt.get(), 0),
      .value = sqlite3_column_int(stmt.get(), 1),
      .next = sqlite3_column_int(stmt.get(), 2),
      .carry = sqlite3_column_int(stmt.get(), 3) != 0,
  };
  if (sqlite3_step(stmt.get()) != SQLITE_DONE) {
    throw StoreError("the table digit holds more than one row");
  }
  return row;
}

} // namespace aaas::digit
