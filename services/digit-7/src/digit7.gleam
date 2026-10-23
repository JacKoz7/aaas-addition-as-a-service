//// SPDX-License-Identifier: MIT
//// Copyright (c) 2026 AaaS Contributors
////
//// Component:       digit-7
//// Module:          src/digit7.gleam
//// Owning Team:     Arithmetic Excellence Center (AEC)
//// Classification:  INTERNAL
//// Purpose:         Entry point of the digit-7 service: configuration,
////                  start-up checks, the HTTP server and the graceful stop
////                  on SIGTERM.
//// Related Docs:    services/digit-7/README.md, CLAUDE.md 4.4, CLAUDE.md 6.1,
////                  ADR-0022, ADR-0029
////
//// The digit-7 service: the authoritative source of the value and the
//// successor of digit 7.
////
//// `main` reads the configuration from the environment
//// (`AAAS_BOOTSTRAP=env`, the only mode before P5.2), opens and migrates
//// the SQLite database, checks that it holds the configured digit, serves
//// the contract and waits for SIGTERM. Any start-up failure is logged and
//// ends the process with exit status 1.

import digit7/api
import digit7/log.{type Logger}
import digit7/metrics
import digit7/server
import digit7/signal
import digit7/store
import envoy
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Version of the service, reported by `digit_build_info`.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-7 0.1.0.
pub const service_version = "0.1.0"

/// The configuration of the service.
///
/// Thread Safety: an immutable value. Owner: AEC. Since: digit-7 0.1.0.
pub type Config {
  /// The digit, the HTTP port, the database file and the migrations.
  Config(digit: Int, port: Int, db_path: String, migrations_dir: String)
}

/// An environment variable, or a fallback when unset or empty.
///
/// Parameters: `name` — the variable; `fallback` — the default.
/// Returns: the value. Errors: none. Side Effects: reads the environment.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `env_or("AAAS_HTTP_PORT", "8080")`.
pub fn env_or(name: String, fallback: String) -> String {
  case envoy.get(name) {
    Ok("") | Error(Nil) -> fallback
    Ok(value) -> value
  }
}

/// Parse a decimal integer of 1 to 9 ASCII digits within a range.
///
/// Parameters: `text` — the text; `low`, `high` — the inclusive range.
/// Returns: the integer. Errors: `Nil` for signs, spaces, other
/// characters, more than 9 digits or a value outside the range.
/// Side Effects: none. Complexity: O(n). Thread Safety: pure. Owner: AEC.
/// Since: digit-7 0.1.0.
/// Example: `parse_int("8080", 1, 65_535) == Ok(8080)`.
pub fn parse_int(text: String, low: Int, high: Int) -> Result(Int, Nil) {
  let graphemes = string.to_graphemes(text)
  let length = list.length(graphemes)
  case
    length >= 1
    && length <= 9
    && list.all(graphemes, string.contains("0123456789", _))
  {
    False -> Error(Nil)
    True ->
      int.parse(text)
      |> result.try(fn(value) {
        case value >= low && value <= high {
          True -> Ok(value)
          False -> Error(Nil)
        }
      })
  }
}

/// Read the configuration from the environment.
///
/// Description: `AAAS_BOOTSTRAP` must be `env`; `AAAS_DIGIT` (default 7)
/// must be 0..9; `AAAS_HTTP_PORT` (default 8080) 1..65535;
/// `AAAS_DB_PATH` defaults to `/data/digit-7.db` and `AAAS_MIGRATIONS_DIR`
/// to `/app/migrations`.
/// Business Justification: configuration only through the environment,
/// no hard-coded hosts (CLAUDE.md 6.1).
/// Parameters: `logger` — logs the reason of a rejection. Returns: the
/// configuration. Errors: `Nil` for an invalid value, after logging it.
/// Side Effects: reads the environment; may log. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-7 0.1.0.
/// Example: `load_config(logger)`.
pub fn load_config(logger: Logger) -> Result(Config, Nil) {
  let bootstrap = env_or("AAAS_BOOTSTRAP", "env")
  let digit = env_or("AAAS_DIGIT", "7")
  let port = env_or("AAAS_HTTP_PORT", "8080")
  case bootstrap, parse_int(digit, 0, 9), parse_int(port, 1, 65_535) {
    "env", Ok(digit), Ok(port) ->
      Ok(Config(
        digit:,
        port:,
        db_path: env_or("AAAS_DB_PATH", "/data/digit-7.db"),
        migrations_dir: env_or("AAAS_MIGRATIONS_DIR", "/app/migrations"),
      ))
    "env", Error(Nil), _ -> {
      log.event(logger, log.Error, "AAAS_DIGIT must be 0..9", Some(digit))
      Error(Nil)
    }
    "env", _, Error(Nil) -> {
      log.event(
        logger,
        log.Error,
        "AAAS_HTTP_PORT must be 1..65535",
        Some(port),
      )
      Error(Nil)
    }
    _, _, _ -> {
      log.event(
        logger,
        log.Error,
        "unsupported AAAS_BOOTSTRAP; only env exists before P5.2",
        Some(bootstrap),
      )
      Error(Nil)
    }
  }
}

/// Open and migrate the database and check the digit it holds.
///
/// Parameters: `config` — the configuration; `logger` — the logger.
/// Returns: the store. Errors: `Nil` after logging when the database
/// cannot be opened, migrated or read, or holds another digit (a volume
/// of another digit service mounted by mistake).
/// Side Effects: opens the file, applies migrations, logs.
/// Complexity: that of the migrations. Thread Safety: safe.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `prepare(config, logger)`.
fn prepare(config: Config, logger: Logger) -> Result(store.Store, Nil) {
  let prepared = {
    use opened <- result.try(store.open(config.db_path, logger))
    use _ <- result.try(store.migrate(opened, config.migrations_dir))
    use row <- result.try(store.read(opened))
    Ok(#(opened, row))
  }
  case prepared {
    Error(store.StoreError(message)) -> {
      log.event(
        logger,
        log.Error,
        "the database cannot be prepared",
        Some(message),
      )
      Error(Nil)
    }
    Ok(#(opened, row)) if row.digit != config.digit -> {
      store.close(opened)
      log.event(
        logger,
        log.Error,
        "the database does not hold the configured digit",
        Some(config.db_path),
      )
      Error(Nil)
    }
    Ok(#(opened, _)) -> Ok(opened)
  }
}

/// Start the service and serve until SIGTERM.
///
/// Parameters: `logger` — the logger. Returns: the exit status: 0 after a
/// graceful stop, 1 when the start fails. Errors: none (failures are
/// logged and give status 1). Side Effects: binds the port, serves
/// requests, logs `listening`, `shutting down` and `stopped`.
/// Complexity: runs until stopped. Thread Safety: call once.
/// Owner: AEC. Since: digit-7 0.1.0. Example: `run(logger)`.
pub fn run(logger: Logger) -> Int {
  let started = {
    use config <- result.try(load_config(logger))
    use opened <- result.try(prepare(config, logger))
    let terminate = process.new_subject()
    signal.install(terminate)
    use contract <- result.try(
      api.start(api.State(
        store: opened,
        digit: config.digit,
        metrics: metrics.new(config.digit, service_version),
        log: logger,
      ))
      |> result.map_error(fn(_) {
        log.event(logger, log.Error, "cannot start the contract process", None)
      }),
    )
    use running <- result.try(
      server.start(config.port, contract, logger)
      |> result.map_error(fn(reason) {
        log.event(
          logger,
          log.Error,
          "cannot start the HTTP server",
          Some("port " <> int.to_string(config.port) <> ": " <> reason),
        )
      }),
    )
    log.event(
      logger,
      log.Info,
      "listening",
      Some(
        "port "
        <> int.to_string(running.port)
        <> ", digit "
        <> int.to_string(config.digit)
        <> ", version "
        <> service_version,
      ),
    )
    Ok(#(running, terminate))
  }
  case started {
    Error(Nil) -> 1
    Ok(#(running, terminate)) -> {
      process.receive_forever(terminate)
      log.event(logger, log.Info, "shutting down", Some("SIGTERM"))
      server.stop(running)
      log.event(logger, log.Info, "stopped", None)
      0
    }
  }
}

/// `erlang:halt/1`: end the runtime with an exit status.
///
/// Parameters: `status` — the exit status. Returns: never.
/// Errors: none. Side Effects: flushes output and ends the OS process.
/// Complexity: O(1). Thread Safety: safe. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `halt(0)`.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Entry point: run the service and exit with its status.
///
/// Business Justification: digit 7 must be served for the successor
/// service to count past it (CLAUDE.md 3, step 7).
/// Parameters: none. Returns: never (the runtime halts). Errors: none.
/// Side Effects: see `run`. Complexity: runs until stopped.
/// Thread Safety: called once by the runtime. Owner: AEC.
/// Since: digit-7 0.1.0. Example: `gleam run`.
pub fn main() -> Nil {
  let logger =
    log.Logger(
      service: env_or("AAAS_SERVICE", "digit-7"),
      threshold: log.parse_level(env_or("AAAS_LOG_LEVEL", "info"), log.Info),
      sink: None,
    )
  halt(run(logger))
}
