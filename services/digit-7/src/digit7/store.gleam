//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7/store.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         The service's own SQLite database: versioned migrations
////                  applied at start-up and the read of the digit row.
//// Related Docs:    services/digit-7/migrations/0001_digit.sql, CLAUDE.md 4.4,
////                  CLAUDE.md 6.1, ADR-0022, ADR-0029
////
//// Access to the digit-7 SQLite database through `sqlight` (the `esqlite`
//// NIF, which embeds SQLite).
////
//// The value and the successor of the digit are read from the table
//// `digit` on every request, never from constants in the code
//// (CLAUDE.md 4.4).

import digit7/log.{type Logger}
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/charlist.{type Charlist}
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import sqlight

/// Milliseconds SQLite waits for a lock held by another connection.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
const busy_timeout_ms = 2000

/// The table that records applied migrations.
///
/// Owner: AEC. Since: digit-7 0.1.0.
const migrations_table =
  "CREATE TABLE IF NOT EXISTS schema_migrations ("
  <> " version TEXT PRIMARY KEY NOT NULL, applied_at TEXT NOT NULL) STRICT;"

/// An open database and the logger of its events.
///
/// Thread Safety: the connection must be used by one process at a time;
/// the service gives it to the contract process only (`digit7/api`).
/// Owner: AEC. Since: digit-7 0.1.0.
pub type Store {
  /// A store over an open `sqlight` connection.
  Store(connection: sqlight.Connection, log: Logger)
}

/// A failure of the database.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type StoreError {
  /// What failed, in words fit for a log line.
  StoreError(message: String)
}

/// The one row of the table `digit`.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type DigitRow {
  /// The digit, its value, its successor and whether the successor carries.
  DigitRow(digit: Int, value: Int, next: Int, carry: Bool)
}

/// The text of a `sqlight` error.
///
/// Parameters: `error` — the error. Returns: its message. Errors: none.
/// Side Effects: none. Complexity: O(1). Thread Safety: pure.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `describe(error) == "no such table: digit"`.
fn describe(error: sqlight.Error) -> String {
  error.message
}

/// Open (or create) the database file.
///
/// Description: sets a busy timeout of `busy_timeout_ms` and turns
/// foreign keys on.
/// Business Justification: each AaaS service owns its database
/// (CLAUDE.md 1, rule 4); the file lives in the `digit-7-data` volume.
/// Parameters: `path` — the file path, or `:memory:`; `log` — the logger
/// of migration events. Returns: the store.
/// Errors: `StoreError` when the file cannot be opened or configured.
/// Side Effects: opens or creates the file. Complexity: O(1).
/// Thread Safety: safe; the store it returns is not. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `open("/data/digit-7.db", logger)`.
pub fn open(path: String, log: Logger) -> Result(Store, StoreError) {
  use connection <- result.try(
    sqlight.open(path)
    |> result.map_error(fn(error) {
      StoreError("cannot open the database: " <> describe(error))
    }),
  )
  let store = Store(connection:, log:)
  use _ <- result.try(execute(
    store,
    "PRAGMA busy_timeout = "
      <> string.inspect(busy_timeout_ms)
      <> "; PRAGMA foreign_keys = ON;",
  ))
  Ok(store)
}

/// Close the database.
///
/// Parameters: `store` — the store. Returns: Nil. Errors: none (a failed
/// close is ignored). Side Effects: closes the file. Complexity: O(1).
/// Thread Safety: not safe; call from the owning process. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `close(store)`.
pub fn close(store: Store) -> Nil {
  let _ = sqlight.close(store.connection)
  Nil
}

/// Run SQL statements that return no rows.
///
/// Parameters: `store` — the store; `sql` — one or more statements.
/// Returns: Nil. Errors: `StoreError` with SQLite's message.
/// Side Effects: changes the database as the statements say.
/// Complexity: that of the statements. Thread Safety: not safe.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `execute(store, "PRAGMA foreign_keys = ON;")`.
pub fn execute(store: Store, sql: String) -> Result(Nil, StoreError) {
  sqlight.exec(sql, store.connection)
  |> result.map_error(fn(error) { StoreError(describe(error)) })
}

/// Whether a migration was already applied.
///
/// Parameters: `store` — the store; `version` — the migration file name.
/// Returns: True when `schema_migrations` lists it; False otherwise or
/// when the table cannot be read. Errors: none. Side Effects: reads the
/// database. Complexity: O(log n). Thread Safety: not safe. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `is_applied(store, "0001_digit.sql")`.
pub fn is_applied(store: Store, version: String) -> Bool {
  case
    sqlight.query(
      "SELECT 1 FROM schema_migrations WHERE version = ?1;",
      on: store.connection,
      with: [sqlight.text(version)],
      expecting: decode.at([0], decode.int),
    )
  {
    Ok([_, ..]) -> True
    _ -> False
  }
}

/// `file:list_dir/1`: the names in a directory.
///
/// Parameters: `dir` — the directory. Returns: the names as charlists, or
/// the POSIX reason. Errors: as the result says. Side Effects: reads the
/// directory. Complexity: O(n). Thread Safety: safe. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `list_dir("/app/migrations")`.
@external(erlang, "file", "list_dir")
fn list_dir(dir: String) -> Result(List(Charlist), Dynamic)

/// `file:read_file/1`: the bytes of a file.
///
/// Parameters: `path` — the file. Returns: its bytes or the POSIX reason.
/// Errors: as the result says. Side Effects: reads the file.
/// Complexity: O(n). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read_file("/app/migrations/0001_digit.sql")`.
@external(erlang, "file", "read_file")
fn read_file(path: String) -> Result(BitArray, Dynamic)

/// The migration files of a directory, in version order.
///
/// Description: every name ending in `.sql` that does not start with a
/// dot, sorted by name (the `NNNN_` prefix gives the order).
/// Parameters: `dir` — the directory. Returns: the names.
/// Errors: `StoreError` when the directory cannot be read.
/// Side Effects: reads the directory. Complexity: O(n log n).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `list_migrations("migrations") == Ok(["0001_digit.sql"])`.
pub fn list_migrations(dir: String) -> Result(List(String), StoreError) {
  case list_dir(dir) {
    Error(_) ->
      Error(StoreError("cannot read the migrations directory " <> dir))
    Ok(names) ->
      names
      |> list.map(charlist.to_string)
      |> list.filter(fn(name) {
        !string.starts_with(name, ".") && string.ends_with(name, ".sql")
      })
      |> list.sort(string.compare)
      |> Ok
  }
}

/// Apply one migration in its own transaction.
///
/// Description: runs the file and records it in `schema_migrations`
/// between `BEGIN IMMEDIATE` and `COMMIT`; on failure rolls back, so a
/// migration is applied whole or not at all.
/// Parameters: `store` — the store; `dir` — the directory; `version` — the
/// file name. Returns: Nil. Errors: `StoreError` naming the migration.
/// Side Effects: changes the schema and data; logs `migration applied`.
/// Complexity: that of the migration. Thread Safety: not safe.
/// Owner: AEC. Since: digit-7 0.1.0.
/// Example: `apply(store, "migrations", "0001_digit.sql")`.
fn apply(
  store: Store,
  dir: String,
  version: String,
) -> Result(Nil, StoreError) {
  use sql <- result.try(
    read_file(dir <> "/" <> version)
    |> result.map_error(fn(_) { Nil })
    |> result.try(bit_array.to_string)
    |> result.replace_error(StoreError("cannot read migration " <> version)),
  )
  let applied = {
    use _ <- result.try(execute(store, "BEGIN IMMEDIATE;"))
    use _ <- result.try(execute(store, sql))
    use _ <- result.try(
      sqlight.query(
        "INSERT INTO schema_migrations (version, applied_at) "
          <> "VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));",
        on: store.connection,
        with: [sqlight.text(version)],
        expecting: decode.success(Nil),
      )
      |> result.map_error(fn(error) { StoreError(describe(error)) }),
    )
    execute(store, "COMMIT;")
  }
  case applied {
    Ok(Nil) -> {
      log.event(store.log, log.Info, "migration applied", Some(version))
      Ok(Nil)
    }
    Error(StoreError(message)) -> {
      let _ = execute(store, "ROLLBACK;")
      Error(StoreError("migration " <> version <> " failed: " <> message))
    }
  }
}

/// Apply every migration of a directory that is not applied yet.
///
/// Business Justification: migrations run at start-up (CLAUDE.md 6.1),
/// so a new volume is seeded and an existing one is brought up to date.
/// Parameters: `store` — the store; `dir` — the migrations directory.
/// Returns: the number of migrations applied (0 when up to date).
/// Errors: `StoreError` for an unreadable directory or a failed migration
/// (the migrations before it stay applied).
/// Side Effects: creates `schema_migrations`, changes the database, logs
/// each migration. Complexity: that of the migrations.
/// Thread Safety: not safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `migrate(store, "/app/migrations") == Ok(1)`.
pub fn migrate(store: Store, dir: String) -> Result(Int, StoreError) {
  use _ <- result.try(execute(store, migrations_table))
  use names <- result.try(list_migrations(dir))
  names
  |> list.filter(fn(name) { !is_applied(store, name) })
  |> list.try_fold(0, fn(applied, name) {
    apply(store, dir, name) |> result.replace(applied + 1)
  })
}

/// Decoder of one row of the table `digit`.
///
/// Parameters: none. Returns: a decoder of the columns digit, value,
/// next and carry. Errors: none. Side Effects: none. Complexity: O(1).
/// Thread Safety: pure. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `decode.run(row, row_decoder())`.
fn row_decoder() -> decode.Decoder(DigitRow) {
  use digit <- decode.field(0, decode.int)
  use value <- decode.field(1, decode.int)
  use next <- decode.field(2, decode.int)
  use carry <- decode.field(3, decode.int)
  decode.success(DigitRow(digit:, value:, next:, carry: carry != 0))
}

/// Read the digit row.
///
/// Business Justification: the value and successor of the digit come
/// from the service's own database on every request (CLAUDE.md 4.4).
/// Parameters: `store` — the store. Returns: the one row.
/// Errors: `StoreError` when the query fails (for example a missing
/// table), when the table is empty or holds more than one row.
/// Side Effects: reads the database. Complexity: O(1).
/// Thread Safety: not safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `read(store) == Ok(DigitRow(7, 7, 8, False))`.
pub fn read(store: Store) -> Result(DigitRow, StoreError) {
  case
    sqlight.query(
      "SELECT digit, value, next, carry FROM digit LIMIT 2;",
      on: store.connection,
      with: [],
      expecting: row_decoder(),
    )
  {
    Error(error) -> Error(StoreError(describe(error)))
    Ok([row]) -> Ok(row)
    Ok([]) -> Error(StoreError("the table digit holds no row"))
    Ok(_) -> Error(StoreError("the table digit holds more than one row"))
  }
}
