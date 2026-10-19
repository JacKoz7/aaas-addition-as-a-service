// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          lib/src/store.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         SQLite storage of the digit: opening the database,
//                  applying the versioned migrations and reading the row
//                  that holds the value and successor of the digit.
// Related Docs:    services/digit-5/README.md, migrations/0001_digit.sql,
//                  CLAUDE.md 4.4, ADR-0022

/// SQLite storage of the digit (open, migrate, read).
///
/// The digit service keeps its only fact, the value and successor of its
/// digit, in its own SQLite database (CLAUDE.md 4.4). Migrations are the
/// files NNNN_*.sql of the migrations directory, applied once each in
/// lexical order and recorded in the table schema_migrations.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'log.dart';

/// Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1).
///
/// Owner: AEC. Since: digit-5 0.1.0.
const int _busyTimeoutMs = 2000;

/// Bookkeeping table of the migration runner: one row per applied file,
/// version is the file name, applied_at the UTC time (ISO 8601).
///
/// Owner: AEC. Since: digit-5 0.1.0.
const String _migrationsTable =
    'CREATE TABLE IF NOT EXISTS schema_migrations ('
    ' version TEXT PRIMARY KEY NOT NULL, applied_at TEXT NOT NULL) STRICT;';

/// A storage failure: the database cannot be opened, migrated or read.
///
/// Business Justification: callers handle one exception type, whatever
/// SQLite or the file system reported.
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
class StoreException implements Exception {
  /// Create the exception.
  ///
  /// Parameters:
  /// - [message]: what failed, with the SQLite message when there is one.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `throw StoreException('the table digit holds no row');`
  ///
  /// See Also: [Store].
  const StoreException(this.message);

  /// What failed.
  final String message;

  /// The message, for logs.
  ///
  /// Returns: [message].
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
  /// safe. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `'$exception'`.
  ///
  /// See Also: [message].
  @override
  String toString() => message;
}

/// The digit row of the database (table digit of 0001_digit.sql).
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
typedef DigitRow = ({int digit, int value, int next, bool carry});

/// The SQLite database of the service (one connection), closed by [close].
///
/// Business Justification: each service owns its database (CLAUDE.md 1,
/// rule 4).
///
/// Thread Safety: one isolate; the sqlite3 package is synchronous, so a
/// call is never interleaved with another request.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
class Store {
  /// Open (or create) the SQLite database file.
  ///
  /// Description: opens [path] read-write, creating it when missing, sets
  /// a busy timeout of 2 s and enables foreign keys.
  ///
  /// Business Justification: each service owns its database.
  ///
  /// Parameters:
  /// - [path]: database file path; `:memory:` for an in-memory database.
  /// - [log]: logger for the migration runner.
  ///
  /// Errors: [StoreException] when SQLite cannot open the file.
  /// Side Effects: creates the file when missing. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final store = Store.open('/data/digit-5.db', log);`
  ///
  /// See Also: [migrate], [close].
  factory Store.open(String path, Logger log) {
    try {
      final db = sqlite3.open(path)
        ..execute('PRAGMA busy_timeout = $_busyTimeoutMs;')
        ..execute('PRAGMA foreign_keys = ON;');
      return Store._(db, log);
    } on SqliteException catch (e) {
      throw StoreException('cannot open the database: ${e.message}');
    }
  }

  /// Wrap an open connection.
  ///
  /// Parameters:
  /// - [_db]: the open connection.
  /// - [_log]: logger for the migration runner.
  ///
  /// Errors: none. Side Effects: none. Complexity: O(1).
  /// Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `Store._(sqlite3.openInMemory(), log)`.
  ///
  /// See Also: [Store.open].
  Store._(this._db, this._log);

  /// The open connection.
  final Database _db;

  /// Logger of the migration runner.
  final Logger _log;

  /// Close the connection.
  ///
  /// Errors: none. Side Effects: releases the connection. Complexity: O(1).
  /// Thread Safety: not safe while a request uses the store. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `store.close();`
  ///
  /// See Also: [Store.open].
  void close() => _db.close();

  /// Execute one or more SQL statements without results.
  ///
  /// Description: used by the migration runner and by the unit tests.
  ///
  /// Business Justification: one place where SQL errors become
  /// [StoreException].
  ///
  /// Parameters:
  /// - [sql]: SQL text.
  ///
  /// Errors: [StoreException] with the SQLite message when a statement
  /// fails. Side Effects: whatever the SQL does. Complexity: that of the
  /// statements. Thread Safety: one isolate. Owner: AEC.
  /// Since: digit-5 0.1.0.
  ///
  /// Example: `store.execute('UPDATE digit SET next = 7;');`
  ///
  /// See Also: [migrate].
  void execute(String sql) {
    try {
      _db.execute(sql);
    } on SqliteException catch (e) {
      throw StoreException(e.message);
    }
  }

  /// Whether a migration is recorded in schema_migrations.
  ///
  /// Description: a failing query counts as "not applied", so that the
  /// following apply fails loudly instead of skipping silently.
  ///
  /// Business Justification: each migration runs exactly once.
  ///
  /// Parameters:
  /// - [version]: migration file name.
  ///
  /// Returns: true when recorded.
  ///
  /// Errors: none. Side Effects: one SELECT. Complexity: O(log m).
  /// Thread Safety: one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `store.isApplied('0001_digit.sql')`.
  ///
  /// See Also: [migrate].
  bool isApplied(String version) {
    try {
      return _db.select('SELECT 1 FROM schema_migrations WHERE version = ?;', [
        version,
      ]).isNotEmpty;
    } on SqliteException {
      return false;
    }
  }

  /// Apply one migration file and record it, in one transaction.
  ///
  /// Description: on any failure the transaction is rolled back.
  ///
  /// Business Justification: a half-applied migration must never be
  /// recorded as applied.
  ///
  /// Parameters:
  /// - [dir]: migrations directory.
  /// - [version]: migration file name inside [dir].
  ///
  /// Errors: [StoreException] when the file cannot be read or its SQL or
  /// the record fails. Side Effects: writes the database; logs the applied
  /// file. Complexity: O(s) in the file size. Thread Safety: one isolate.
  /// Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `store._apply('/app/migrations', '0001_digit.sql');`
  ///
  /// See Also: [migrate].
  void _apply(String dir, String version) {
    final String sql;
    try {
      sql = File('$dir/$version').readAsStringSync();
    } on FileSystemException catch (e) {
      throw StoreException('cannot read migration $version: ${e.message}');
    }
    try {
      _db
        ..execute('BEGIN IMMEDIATE;')
        ..execute(sql)
        ..execute(
          'INSERT INTO schema_migrations (version, applied_at) '
          "VALUES (?, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));",
          [version],
        )
        ..execute('COMMIT;');
    } on SqliteException catch (e) {
      if (!_db.autocommit) {
        _db.execute('ROLLBACK;');
      }
      throw StoreException('migration $version failed: ${e.message}');
    }
    _log.write(Level.info, 'migration applied', detail: version);
  }

  /// Apply the migrations of a directory that are not applied yet.
  ///
  /// Description: creates schema_migrations when missing, lists the files
  /// *.sql of [dir] that do not start with a dot, sorts them lexically and
  /// applies each file not recorded yet, in one transaction per file with
  /// its record. Running it again applies nothing.
  ///
  /// Business Justification: migrations run at start-up and are versioned
  /// (CLAUDE.md 6.1); the seed of the digit is a migration, so the digit
  /// lives in the database, not the code.
  ///
  /// Parameters:
  /// - [dir]: directory with the migration files.
  ///
  /// Returns: the number of files applied by this call.
  ///
  /// Errors: [StoreException] when the directory or a file cannot be read
  /// or its SQL fails. Side Effects: reads files; writes the database; logs
  /// each applied file. Complexity: O(f log f + s). Thread Safety: call
  /// before serving. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final applied = store.migrate('/app/migrations');`
  ///
  /// See Also: [read].
  int migrate(String dir) {
    execute(_migrationsTable);
    final List<String> names;
    try {
      names =
          Directory(dir)
              .listSync()
              .whereType<File>()
              .map((file) => file.uri.pathSegments.last)
              .where((name) => !name.startsWith('.') && name.endsWith('.sql'))
              .toList()
            ..sort();
    } on FileSystemException {
      throw StoreException('cannot read the migrations directory $dir');
    }
    var applied = 0;
    for (final name in names) {
      if (!isApplied(name)) {
        _apply(dir, name);
        applied++;
      }
    }
    return applied;
  }

  /// Read the digit row.
  ///
  /// Description: requires the table digit to hold exactly one row; zero
  /// rows or more than one are an error, as is any SQLite failure.
  ///
  /// Business Justification: GET /value, GET /next and GET /health answer
  /// from this read on every request (CLAUDE.md 4.4).
  ///
  /// Returns: the row.
  ///
  /// Errors: [StoreException] when the query fails or the table does not
  /// hold exactly one row. Side Effects: one SELECT. Complexity: O(1).
  /// Thread Safety: one isolate. Owner: AEC. Since: digit-5 0.1.0.
  ///
  /// Example: `final row = store.read();`
  ///
  /// See Also: [DigitRow].
  DigitRow read() {
    final ResultSet rows;
    try {
      rows = _db.select('SELECT digit, value, next, carry FROM digit LIMIT 2;');
    } on SqliteException catch (e) {
      throw StoreException(e.message);
    }
    if (rows.isEmpty) {
      throw const StoreException('the table digit holds no row');
    }
    if (rows.length > 1) {
      throw const StoreException('the table digit holds more than one row');
    }
    final row = rows.first;
    return (
      digit: row['digit'] as int,
      value: row['value'] as int,
      next: row['next'] as int,
      carry: row['carry'] != 0,
    );
  }
}
