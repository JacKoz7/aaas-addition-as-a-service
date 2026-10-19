// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          src/DigitService/Store.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         SQLite storage of the digit: opening the database,
//                  applying the versioned migrations and reading the row
//                  that holds the value and successor of the digit.
// Related Docs:    services/digit-6/README.md, migrations/0001_digit.sql,
//                  CLAUDE.md 4.4, ADR-0022

import CSQLite

#if canImport(Glibc)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#endif

/// Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1).
///
/// Owner: AEC. Since: digit-6 0.1.0.
private let busyTimeoutMs: Int32 = 2000

/// Bookkeeping table of the migration runner: one row per applied file,
/// `version` is the file name, `applied_at` the UTC time (ISO 8601).
///
/// Owner: AEC. Since: digit-6 0.1.0.
private let migrationsTable =
  "CREATE TABLE IF NOT EXISTS schema_migrations ("
  + " version TEXT PRIMARY KEY NOT NULL, applied_at TEXT NOT NULL) STRICT;"

/// The destructor value telling SQLite to copy a bound string
/// (`SQLITE_TRANSIENT`, a macro Swift cannot import).
///
/// Owner: AEC. Since: digit-6 0.1.0.
private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A storage failure: the database cannot be opened, migrated or read.
///
/// Business Justification: callers handle one error type, whatever SQLite
/// or the file system reported.
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public struct StoreError: Error, Equatable, CustomStringConvertible {
  /// What failed, with the SQLite message when there is one.
  public let message: String

  /// The message, for logs.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `"\(error)"`.
  public var description: String { message }
}

/// The digit row of the database (table `digit` of 0001_digit.sql).
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public struct DigitRow: Equatable, Sendable {
  /// The digit the service represents, 0...9.
  public let digit: Int
  /// Numeric value of the digit, 0...9.
  public let value: Int
  /// Successor of the digit in base 10, 0...9.
  public let next: Int
  /// True when the successor wraps to 0 (digit 9 only).
  public let carry: Bool
}

/// The SQLite database of the service (one connection), closed when the
/// object is released.
///
/// Business Justification: each service owns its database (CLAUDE.md 1,
/// rule 4).
///
/// Thread Safety: not synchronised; used before the server starts and then
/// only through ``Api``, which the server calls under one lock (hence
/// `@unchecked Sendable`, ADR-0028).
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
public final class Store: @unchecked Sendable {
  /// The open connection.
  private let db: OpaquePointer
  /// Logger of the migration runner.
  private let log: Logger

  /// Open (or create) the SQLite database file.
  ///
  /// Description: opens `path` read-write, creating it when missing, sets
  /// a busy timeout of 2 s and enables foreign keys.
  ///
  /// Business Justification: each service owns its database.
  ///
  /// - Parameters:
  ///   - path: Database file path; `:memory:` for an in-memory database.
  ///   - log: Logger for the migration runner.
  /// - Throws: ``StoreError`` when SQLite cannot open the file.
  ///
  /// Side Effects: creates the file when missing. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let store = try Store(path: "/data/digit-6.db", log: log)`.
  ///
  /// See Also: ``migrate(_:)``.
  public init(path: String, log: Logger) throws {
    var handle: OpaquePointer?
    let status = sqlite3_open_v2(
      path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard status == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
      sqlite3_close(handle)
      throw StoreError(message: "cannot open the database: \(message)")
    }
    db = handle
    self.log = log
    sqlite3_busy_timeout(db, busyTimeoutMs)
    try execute("PRAGMA foreign_keys = ON;")
  }

  /// Close the connection.
  ///
  /// Errors: none. Side Effects: closes the connection. Complexity: O(1).
  /// Thread Safety: called once, when no request uses the store.
  /// Owner: AEC. Since: digit-6 0.1.0.
  deinit {
    sqlite3_close(db)
  }

  /// The last SQLite error message of the connection.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: as
  /// the store. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `throw StoreError(message: lastError)`.
  private var lastError: String { String(cString: sqlite3_errmsg(db)) }

  /// Execute one or more SQL statements without results.
  ///
  /// Description: used by the migration runner and by the unit tests.
  ///
  /// Business Justification: one place where SQL errors become
  /// ``StoreError``.
  ///
  /// - Parameter sql: SQL text.
  /// - Throws: ``StoreError`` with the SQLite message when a statement
  ///   fails.
  ///
  /// Side Effects: whatever the SQL does. Complexity: that of the
  /// statements. Thread Safety: as the store. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `try store.execute("UPDATE digit SET next = 7;")`.
  ///
  /// See Also: ``migrate(_:)``.
  public func execute(_ sql: String) throws {
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
      let message = error.map { String(cString: $0) } ?? lastError
      sqlite3_free(error)
      throw StoreError(message: message)
    }
  }

  /// Whether a migration is recorded in `schema_migrations`.
  ///
  /// Description: a failing query counts as "not applied", so that the
  /// following apply fails loudly instead of skipping silently.
  ///
  /// Business Justification: each migration runs exactly once.
  ///
  /// - Parameter version: Migration file name.
  /// - Returns: True when recorded.
  ///
  /// Errors: none. Side Effects: one SELECT. Complexity: O(log m).
  /// Thread Safety: as the store. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `store.isApplied("0001_digit.sql")`.
  ///
  /// See Also: ``migrate(_:)``.
  public func isApplied(_ version: String) -> Bool {
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard
      sqlite3_prepare_v2(db, "SELECT 1 FROM schema_migrations WHERE version = ?1;", -1, &stmt, nil)
        == SQLITE_OK
    else { return false }
    sqlite3_bind_text(stmt, 1, version, -1, transient)
    return sqlite3_step(stmt) == SQLITE_ROW
  }

  /// Read a whole file as UTF-8 text.
  ///
  /// - Parameter path: File path.
  /// - Returns: The content, or nil when the file cannot be read.
  ///
  /// Errors: none (nil). Side Effects: reads the file. Complexity: O(s).
  /// Thread Safety: safe. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `readFile("/app/migrations/0001_digit.sql")`.
  ///
  /// See Also: ``apply(dir:version:)``.
  private func readFile(_ path: String) -> String? {
    guard let file = fopen(path, "rb") else { return nil }
    defer { fclose(file) }
    var bytes: [UInt8] = []
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = fread(&chunk, 1, chunk.count, file)
      if count == 0 { break }
      bytes += chunk[0..<count]
    }
    return ferror(file) == 0 ? String(decoding: bytes, as: UTF8.self) : nil
  }

  /// Apply one migration file and record it, in one transaction.
  ///
  /// Description: on any failure the transaction is rolled back.
  ///
  /// Business Justification: a half-applied migration must never be
  /// recorded as applied.
  ///
  /// - Parameters:
  ///   - dir: Migrations directory.
  ///   - version: Migration file name inside `dir`.
  /// - Throws: ``StoreError`` when the file cannot be read or its SQL or
  ///   the record fails.
  ///
  /// Side Effects: writes the database; logs the applied file.
  /// Complexity: O(s) in the file size. Thread Safety: as the store.
  /// Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `try apply(dir: "/app/migrations", version: "0001_digit.sql")`.
  ///
  /// See Also: ``migrate(_:)``.
  private func apply(dir: String, version: String) throws {
    guard let sql = readFile(dir + "/" + version) else {
      throw StoreError(message: "cannot read migration \(version)")
    }
    do {
      try execute("BEGIN IMMEDIATE;")
      try execute(sql)
      var stmt: OpaquePointer?
      defer { sqlite3_finalize(stmt) }
      guard
        sqlite3_prepare_v2(
          db,
          "INSERT INTO schema_migrations (version, applied_at) "
            + "VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));", -1, &stmt, nil) == SQLITE_OK
      else { throw StoreError(message: lastError) }
      sqlite3_bind_text(stmt, 1, version, -1, transient)
      guard sqlite3_step(stmt) == SQLITE_DONE else { throw StoreError(message: lastError) }
      try execute("COMMIT;")
    } catch let error as StoreError {
      if sqlite3_get_autocommit(db) == 0 {
        sqlite3_exec(db, "ROLLBACK;", nil, nil, nil)
      }
      throw StoreError(message: "migration \(version) failed: \(error.message)")
    }
    log.write(.info, "migration applied", detail: version)
  }

  /// The names of the `*.sql` files of a directory that do not start with
  /// a dot, sorted lexically.
  ///
  /// - Parameter dir: Directory.
  /// - Returns: The file names, or nil when the directory cannot be read.
  ///
  /// Errors: none (nil). Side Effects: reads the directory.
  /// Complexity: O(f log f). Thread Safety: safe. Owner: AEC.
  /// Since: digit-6 0.1.0.
  ///
  /// Example: `listMigrations("/app/migrations")`.
  ///
  /// See Also: ``migrate(_:)``.
  private func listMigrations(_ dir: String) -> [String]? {
    guard let handle = opendir(dir) else { return nil }
    defer { closedir(handle) }
    var names: [String] = []
    while let entry = readdir(handle) {
      let name = withUnsafePointer(to: entry.pointee.d_name) {
        $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
      }
      if !name.hasPrefix(".") && name.hasSuffix(".sql") {
        names.append(name)
      }
    }
    return names.sorted()
  }

  /// Apply the migrations of a directory that are not applied yet.
  ///
  /// Description: creates `schema_migrations` when missing, lists the
  /// files `*.sql` of `dir` that do not start with a dot, sorts them
  /// lexically and applies each file not recorded yet, in one transaction
  /// per file with its record. Running it again applies nothing.
  ///
  /// Business Justification: migrations run at start-up and are versioned
  /// (CLAUDE.md 6.1); the seed of the digit is a migration, so the digit
  /// lives in the database, not the code.
  ///
  /// - Parameter dir: Directory with the migration files.
  /// - Returns: The number of files applied by this call.
  /// - Throws: ``StoreError`` when the directory or a file cannot be read
  ///   or its SQL fails.
  ///
  /// Side Effects: reads files; writes the database; logs each applied
  /// file. Complexity: O(f log f + s). Thread Safety: call before
  /// serving. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let applied = try store.migrate("/app/migrations")`.
  ///
  /// See Also: ``read()``.
  @discardableResult
  public func migrate(_ dir: String) throws -> Int {
    try execute(migrationsTable)
    guard let names = listMigrations(dir) else {
      throw StoreError(message: "cannot read the migrations directory \(dir)")
    }
    var applied = 0
    for name in names where !isApplied(name) {
      try apply(dir: dir, version: name)
      applied += 1
    }
    return applied
  }

  /// Read the digit row.
  ///
  /// Description: requires the table `digit` to hold exactly one row; zero
  /// rows or more than one are an error, as is any SQLite failure.
  ///
  /// Business Justification: GET /value, GET /next and GET /health answer
  /// from this read on every request (CLAUDE.md 4.4).
  ///
  /// - Returns: The row.
  /// - Throws: ``StoreError`` when the query fails or the table does not
  ///   hold exactly one row.
  ///
  /// Side Effects: one SELECT. Complexity: O(1). Thread Safety: as the
  /// store. Owner: AEC. Since: digit-6 0.1.0.
  ///
  /// Example: `let row = try store.read()`.
  ///
  /// See Also: ``DigitRow``.
  public func read() throws -> DigitRow {
    var stmt: OpaquePointer?
    defer { sqlite3_finalize(stmt) }
    guard
      sqlite3_prepare_v2(db, "SELECT digit, value, next, carry FROM digit LIMIT 2;", -1, &stmt, nil)
        == SQLITE_OK
    else { throw StoreError(message: lastError) }
    guard sqlite3_step(stmt) == SQLITE_ROW else {
      throw StoreError(message: "the table digit holds no row")
    }
    let row = DigitRow(
      digit: Int(sqlite3_column_int(stmt, 0)), value: Int(sqlite3_column_int(stmt, 1)),
      next: Int(sqlite3_column_int(stmt, 2)), carry: sqlite3_column_int(stmt, 3) != 0)
    guard sqlite3_step(stmt) == SQLITE_DONE else {
      throw StoreError(message: "the table digit holds more than one row")
    }
    return row
  }
}
