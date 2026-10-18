// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-1
// Module:          src/store.hpp
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         SQLite storage of the digit: opening the database,
//                  applying the versioned migrations and reading the row
//                  that holds the value and successor of the digit.
// Related Docs:    services/digit-1/README.md, migrations/0001_digit.sql,
//                  CLAUDE.md 4.4, ADR-0022

/**
 * @file store.hpp
 * @brief SQLite storage of the digit (open, migrate, read).
 *
 * @details The digit service keeps its only fact, the value and successor
 * of its digit, in its own SQLite database (CLAUDE.md 4.4). Migrations are
 * the files `NNNN_*.sql` of the migrations directory, applied once each in
 * lexical order and recorded in the table `schema_migrations`.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 */

#ifndef DIGIT_STORE_HPP
#define DIGIT_STORE_HPP

#include <filesystem>
#include <memory>
#include <sqlite3.h>
#include <stdexcept>
#include <string>

namespace aaas::digit {

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
 * @since digit-1 0.1.0
 * @see Store::read
 */
struct DigitRow {
  int digit = 0;      ///< The digit the service represents, 0..9.
  int value = 0;      ///< Numeric value of the digit, 0..9.
  int next = 0;       ///< Successor of the digit in base 10, 0..9.
  bool carry = false; ///< True when the successor wraps to 0 (digit 9 only).

  /// @brief Field-wise equality (used by the unit tests).
  /// @param other Row to compare with.
  /// @return true when every field is equal.
  bool operator==(const DigitRow &other) const = default;
};

/**
 * @brief A storage failure: the database cannot be opened, migrated or read.
 *
 * @details what() carries the SQLite message or the reason.
 *
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @see Store
 */
class StoreError : public std::runtime_error {
public:
  using std::runtime_error::runtime_error;
};

/**
 * @brief The SQLite database of the service (one connection).
 *
 * @details Owns the connection and closes it on destruction (RAII).
 * Movable, not copyable.
 *
 * @par Business Justification
 * Each service owns its database (CLAUDE.md 1, rule 4).
 *
 * @par Thread Safety
 * Not safe: one thread at a time (the Api serialises access with a mutex).
 * @par Owner
 * Arithmetic Excellence Center (AEC)
 * @since digit-1 0.1.0
 * @see Api
 */
class Store {
public:
  /**
   * @brief Open (or create) the SQLite database file.
   *
   * @details Opens @p path read-write, creating it when missing, sets a
   * busy timeout of 2 s and enables foreign keys.
   *
   * @par Business Justification
   * Each service owns its database (CLAUDE.md 1, rule 4).
   *
   * @param path Database file path; `:memory:` for an in-memory database.
   *
   * @par Errors
   * StoreError when SQLite cannot open the file (missing directory,
   * permissions).
   * @par Side Effects
   * Creates the file when missing.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * Safe; the new connection must be used by one thread at a time.
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * Store store("/data/digit-1.db");
   * @endcode
   * @see migrate
   */
  explicit Store(const std::string &path);

  /**
   * @brief Apply the migrations of a directory that are not applied yet.
   *
   * @details Creates `schema_migrations` when missing, lists the regular
   * files of @p dir whose names end in `.sql` (hidden files skipped), sorts
   * them lexically and applies each file whose name is not recorded yet, in
   * one transaction per file together with its record. Running it again
   * applies nothing.
   *
   * @par Business Justification
   * Migrations run at start-up and are versioned (CLAUDE.md 6.1); the seed
   * of the digit is a migration, so the digit lives in the database, not
   * the code.
   *
   * @param dir Directory with the migration files.
   * @return Number of files applied by this call.
   *
   * @par Errors
   * StoreError when the directory or a file cannot be read, or its SQL
   * fails; the failing file is rolled back.
   * @par Side Effects
   * Reads files; writes the database; logs every applied file.
   * @par Complexity
   * O(f log f + s) for f files of total size s.
   * @par Thread Safety
   * Not safe; call before serving requests.
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * int applied = store.migrate("/app/migrations");
   * @endcode
   * @see read
   */
  int migrate(const std::filesystem::path &dir);

  /**
   * @brief Read the digit row.
   *
   * @details Requires the table `digit` to hold exactly one row; zero rows
   * or more than one are an error, as is any SQLite failure.
   *
   * @par Business Justification
   * GET /value, GET /next and GET /health answer from this read on every
   * request (CLAUDE.md 4.4).
   *
   * @return The row.
   *
   * @par Errors
   * StoreError when the query fails or the table does not hold exactly one
   * row.
   * @par Side Effects
   * One SELECT.
   * @par Complexity
   * O(1).
   * @par Thread Safety
   * As the connection: one thread at a time.
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * DigitRow row = store.read(); // {1, 1, 2, false}
   * @endcode
   * @see DigitRow
   */
  [[nodiscard]] DigitRow read() const;

  /**
   * @brief Execute one or more SQL statements without results.
   *
   * @details Used by the migration runner and by the unit tests to change
   * the row.
   *
   * @par Business Justification
   * One place where SQL errors become StoreError.
   *
   * @param sql SQL text.
   *
   * @par Errors
   * StoreError with the SQLite message when a statement fails.
   * @par Side Effects
   * Whatever @p sql does to the database.
   * @par Complexity
   * That of the statements.
   * @par Thread Safety
   * As the connection.
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * store.execute("UPDATE digit SET next = 7;");
   * @endcode
   * @see migrate
   */
  void execute(const std::string &sql);

private:
  /**
   * @brief Closes a connection (deleter of @ref db_).
   *
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   */
  struct Closer {
    /// @brief Close the connection.
    /// @param db Connection; may be null.
    void operator()(sqlite3 *db) const noexcept { sqlite3_close(db); }
  };

  /**
   * @brief Whether a migration is already recorded in `schema_migrations`.
   *
   * @details A failing query counts as "not applied", so that the
   * following apply fails loudly instead of skipping silently.
   *
   * @par Business Justification
   * Each migration runs exactly once.
   *
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
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * if (!is_applied("0001_digit.sql")) { ... }
   * @endcode
   * @see migrate
   */
  [[nodiscard]] bool is_applied(const std::string &version) const;

  /**
   * @brief Apply one migration file and record it, in one transaction.
   *
   * @details On any failure the transaction is rolled back.
   *
   * @par Business Justification
   * A half-applied migration must never be recorded as applied.
   *
   * @param file Path of the migration file; its name is the version.
   *
   * @par Errors
   * StoreError when the file cannot be read or its SQL or the record fails.
   * @par Side Effects
   * Writes the database; logs the applied file.
   * @par Complexity
   * O(s) in the size of the file.
   * @par Thread Safety
   * As the connection.
   * @par Owner
   * Arithmetic Excellence Center (AEC)
   * @since digit-1 0.1.0
   * @par Example
   * @code
   * apply("/app/migrations/0001_digit.sql");
   * @endcode
   * @see migrate
   */
  void apply(const std::filesystem::path &file);

  std::unique_ptr<sqlite3, Closer> db_; ///< The open connection.
};

} // namespace aaas::digit

#endif // DIGIT_STORE_HPP
