// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/store.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         SQLite storage of the digit: opening the database,
//                  applying the versioned migrations and reading the row
//                  that holds the value and successor of the digit.
// Related Docs:    services/digit-8/README.md, migrations/0001_digit.sql,
//                  CLAUDE.md 4.4, ADR-0022

/**
 * SQLite storage of the digit-8 service, through the C API binding that
 * ships with Phobos (`etc.c.sqlite3`).
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.store;

import digit8.log : Level, Logger;
import etc.c.sqlite3;
import std.algorithm.iteration : filter, map;
import std.algorithm.searching : endsWith, startsWith;
import std.algorithm.sorting : sort;
import std.array : array;
import std.exception : collectException;
import std.file : dirEntries, FileException, readText, SpanMode;
import std.path : baseName, buildPath;
import std.string : fromStringz, toStringz;

/// Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1).
private enum int busyTimeoutMs = 2000;

/**
 * Bookkeeping table of the migration runner: one row per applied file;
 * `version` is the file name, `applied_at` the UTC time (ISO 8601).
 */
private enum string migrationsTable = "CREATE TABLE IF NOT EXISTS schema_migrations ("
    ~ " version TEXT PRIMARY KEY NOT NULL, applied_at TEXT NOT NULL) STRICT;";

/**
 * A storage failure: the database cannot be opened, migrated or read.
 *
 * Business_Justification: callers handle one error type, whatever SQLite
 * or the file system reported.
 *
 * Thread_Safety: immutable after construction.
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class StoreException : Exception
{
    /**
     * Create the exception.
     *
     * Params:
     *   message = what failed, with the SQLite message when there is one.
     *   file = source file of the throw (filled in by the compiler).
     *   line = source line of the throw (filled in by the compiler).
     *
     * Errors: none. Side Effects: none. Complexity: O(1).
     * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    this(string message, string file = __FILE__, size_t line = __LINE__) pure nothrow @safe
    {
        super(message, file, line);
    }
}

/**
 * The digit row of the database (table `digit` of 0001_digit.sql).
 *
 * Thread_Safety: a value type. Owner: Arithmetic Excellence Center (AEC).
 * Since: digit-8 0.1.0.
 */
struct DigitRow
{
    /// The digit the service represents, 0..9.
    int digit;
    /// Numeric value of the digit, 0..9.
    int value;
    /// Successor of the digit in base 10, 0..9.
    int next;
    /// True when the successor wraps to 0 (digit 9 only).
    bool carry;
}

/**
 * The SQLite database of the service (one connection).
 *
 * Business_Justification: each service owns its database (CLAUDE.md 1,
 * rule 4).
 *
 * Thread_Safety: not synchronised; used before the server starts and then
 * only through `digit8.api.Api`, which the server calls under one mutex
 * (ADR-0030).
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class Store
{
    /// The open connection; `null` after `close`.
    private sqlite3* db;
    /// Logger of the migration runner.
    private Logger log;

    /**
     * Open (or create) the SQLite database file.
     *
     * Description: opens `path` read-write, creating it when missing, sets
     * a busy timeout of 2 s and enables foreign keys.
     *
     * Params:
     *   path = the database file; `:memory:` for an in-memory database.
     *   log = the logger of the migration runner.
     * Throws: `StoreException` when SQLite cannot open the file.
     *
     * Side Effects: creates the file when missing. Complexity: O(1).
     * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
     *
     * Examples: `auto store = new Store("/data/digit-8.db", log);`
     *
     * See_Also: `migrate`.
     */
    this(string path, Logger log) @trusted
    {
        this.log = log;
        sqlite3* handle;
        auto status = sqlite3_open_v2(path.toStringz, &handle,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, null);
        if (status != SQLITE_OK)
        {
            auto message = handle is null ? "out of memory" : sqlite3_errmsg(handle)
                .fromStringz.idup;
            sqlite3_close(handle);
            throw new StoreException("cannot open the database: " ~ message);
        }
        db = handle;
        sqlite3_busy_timeout(db, busyTimeoutMs);
        execute("PRAGMA foreign_keys = ON;");
    }

    /**
     * Close the connection; later calls are no-ops.
     *
     * Errors: none. Side Effects: closes the connection. Complexity: O(1).
     * Thread Safety: call when no request uses the store. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    void close() @trusted nothrow
    {
        if (db !is null)
        {
            sqlite3_close(db);
            db = null;
        }
    }

    /**
     * The last SQLite error message of the connection.
     *
     * Returns: the message.
     *
     * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
     * as the store. Owner: AEC. Since: digit-8 0.1.0.
     */
    private string lastError() @trusted
    {
        return sqlite3_errmsg(db).fromStringz.idup;
    }

    /**
     * Execute one or more SQL statements without results.
     *
     * Description: used by the migration runner and by the unit tests.
     *
     * Business_Justification: one place where SQL errors become
     * `StoreException`.
     *
     * Params:
     *   sql = the SQL text.
     * Throws: `StoreException` with the SQLite message when a statement
     * fails.
     *
     * Side Effects: whatever the SQL does. Complexity: that of the
     * statements. Thread Safety: as the store. Owner: AEC.
     * Since: digit-8 0.1.0.
     *
     * Examples: `store.execute("UPDATE digit SET next = 7;");`
     */
    void execute(string sql) @trusted
    {
        char* error;
        if (sqlite3_exec(db, sql.toStringz, null, null, &error) != SQLITE_OK)
        {
            auto message = error is null ? lastError() : error.fromStringz.idup;
            sqlite3_free(error);
            throw new StoreException(message);
        }
    }

    /**
     * Whether a migration is recorded in `schema_migrations`.
     *
     * Description: a failing query counts as "not applied", so that the
     * following apply fails loudly instead of skipping silently.
     *
     * Business_Justification: each migration runs exactly once.
     *
     * Params:
     *   version_ = the migration file name.
     * Returns: true when recorded.
     *
     * Errors: none. Side Effects: one SELECT. Complexity: O(log m).
     * Thread Safety: as the store. Owner: AEC. Since: digit-8 0.1.0.
     */
    bool isApplied(string version_) @trusted
    {
        sqlite3_stmt* stmt;
        scope (exit)
            sqlite3_finalize(stmt);
        if (sqlite3_prepare_v2(db, "SELECT 1 FROM schema_migrations WHERE version = ?1;",
                -1, &stmt, null) != SQLITE_OK)
        {
            return false;
        }
        sqlite3_bind_text(stmt, 1, version_.ptr, cast(int) version_.length, SQLITE_TRANSIENT);
        return sqlite3_step(stmt) == SQLITE_ROW;
    }

    /**
     * Apply one migration file and record it, in one transaction.
     *
     * Description: on any failure the transaction is rolled back.
     *
     * Business_Justification: a half-applied migration must never be
     * recorded as applied.
     *
     * Params:
     *   dir = the migrations directory.
     *   version_ = the migration file name inside `dir`.
     * Throws: `StoreException` when the file cannot be read or its SQL or
     * the record fails.
     *
     * Side Effects: writes the database; logs the applied file.
     * Complexity: O(s) in the file size. Thread Safety: as the store.
     * Owner: AEC. Since: digit-8 0.1.0.
     */
    private void apply(string dir, string version_) @trusted
    {
        string sql;
        if (collectException(readText(buildPath(dir, version_)), sql) !is null)
        {
            throw new StoreException("cannot read migration " ~ version_);
        }
        try
        {
            execute("BEGIN IMMEDIATE;");
            execute(sql);
            sqlite3_stmt* stmt;
            scope (exit)
                sqlite3_finalize(stmt);
            if (sqlite3_prepare_v2(db, "INSERT INTO schema_migrations (version, applied_at) "
                    ~ "VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));",
                    -1, &stmt, null) != SQLITE_OK)
            {
                throw new StoreException(lastError());
            }
            sqlite3_bind_text(stmt, 1, version_.ptr, cast(int) version_.length, SQLITE_TRANSIENT);
            if (sqlite3_step(stmt) != SQLITE_DONE)
            {
                throw new StoreException(lastError());
            }
            execute("COMMIT;");
        }
        catch (StoreException error)
        {
            if (sqlite3_get_autocommit(db) == 0)
            {
                sqlite3_exec(db, "ROLLBACK;", null, null, null);
            }
            throw new StoreException("migration " ~ version_ ~ " failed: " ~ error.msg);
        }
        log.write(Level.info, "migration applied", version_);
    }

    /**
     * Apply the migrations of a directory that are not applied yet.
     *
     * Description: creates `schema_migrations` when missing, lists the
     * files `*.sql` of `dir` that do not start with a dot, sorts them
     * lexically and applies each file not recorded yet, in one transaction
     * per file with its record. Running it again applies nothing.
     *
     * Business_Justification: migrations run at start-up and are versioned
     * (CLAUDE.md 6.1); the seed of the digit is a migration, so the digit
     * lives in the database, not the code.
     *
     * Params:
     *   dir = the directory with the migration files.
     * Returns: the number of files applied by this call.
     * Throws: `StoreException` when the directory or a file cannot be read
     * or its SQL fails.
     *
     * Side Effects: reads files; writes the database; logs each applied
     * file. Complexity: O(f log f + s). Thread Safety: call before serving.
     * Owner: AEC. Since: digit-8 0.1.0.
     *
     * Examples: `auto applied = store.migrate("/app/migrations");`
     *
     * See_Also: `read`.
     */
    size_t migrate(string dir) @trusted
    {
        execute(migrationsTable);
        string[] names;
        try
        {
            names = dirEntries(dir, SpanMode.shallow).filter!(entry => entry.isFile)
                .map!(entry => baseName(entry.name))
                .filter!(name => !name.startsWith(".") && name.endsWith(".sql"))
                .array;
        }
        catch (FileException)
        {
            throw new StoreException("cannot read the migrations directory " ~ dir);
        }
        names.sort();
        size_t applied = 0;
        foreach (name; names)
        {
            if (!isApplied(name))
            {
                apply(dir, name);
                applied++;
            }
        }
        return applied;
    }

    /**
     * Read the digit row.
     *
     * Description: requires the table `digit` to hold exactly one row;
     * zero rows or more than one are an error, as is any SQLite failure.
     *
     * Business_Justification: GET /value, GET /next and GET /health answer
     * from this read on every request (CLAUDE.md 4.4).
     *
     * Returns: the row.
     * Throws: `StoreException` when the query fails or the table does not
     * hold exactly one row.
     *
     * Side Effects: one SELECT. Complexity: O(1). Thread Safety: as the
     * store. Owner: AEC. Since: digit-8 0.1.0.
     *
     * Examples: `auto row = store.read();`
     *
     * See_Also: `DigitRow`.
     */
    DigitRow read() @trusted
    {
        sqlite3_stmt* stmt;
        scope (exit)
            sqlite3_finalize(stmt);
        if (sqlite3_prepare_v2(db, "SELECT digit, value, next, carry FROM digit LIMIT 2;",
                -1, &stmt, null) != SQLITE_OK)
        {
            throw new StoreException(lastError());
        }
        auto status = sqlite3_step(stmt);
        if (status == SQLITE_DONE)
        {
            throw new StoreException("the table digit holds no row");
        }
        if (status != SQLITE_ROW)
        {
            throw new StoreException(lastError());
        }
        auto row = DigitRow(sqlite3_column_int(stmt, 0), sqlite3_column_int(stmt,
                1), sqlite3_column_int(stmt, 2), sqlite3_column_int(stmt, 3) != 0);
        if (sqlite3_step(stmt) != SQLITE_DONE)
        {
            throw new StoreException("the table digit holds more than one row");
        }
        return row;
    }
}
