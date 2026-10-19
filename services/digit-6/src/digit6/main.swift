// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          src/digit6/main.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Entry point of the digit-6 service: configuration,
//                  start-up checks, the HTTP server and the SIGTERM
//                  handling.
// Related Docs:    services/digit-6/README.md, CLAUDE.md 4.4 and 6.1,
//                  ADR-0022, ADR-0028

import DigitService

#if canImport(Glibc)
  import Glibc
#elseif canImport(Darwin)
  import Darwin
#endif

/// Version of the service (SemVer, docs/CHANGELOG.md).
///
/// Owner: AEC. Since: digit-6 0.1.0.
let serviceVersion = "0.1.0"

/// Configuration of the service, read from the environment.
///
/// Business Justification: no hard-coded hosts, ports or paths
/// (CLAUDE.md 6.1).
///
/// Thread Safety: a value type; safe.
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
struct Config {
  /// The digit the service represents, 0...9 (`AAAS_DIGIT`).
  let digit: Int
  /// HTTP port, 1...65535 (`AAAS_HTTP_PORT`).
  let port: Int
  /// SQLite file (`AAAS_DB_PATH`).
  let dbPath: String
  /// Directory of the migration files (`AAAS_MIGRATIONS_DIR`).
  let migrationsDir: String
}

/// An environment variable, or a fallback when it is unset or empty.
///
/// Business Justification: configuration comes only from the environment
/// until P5.2 (CLAUDE.md 6.1).
///
/// - Parameters:
///   - name: Variable name.
///   - fallback: Value used when unset or empty.
/// - Returns: The value.
///
/// Errors: none. Side Effects: reads the environment. Complexity: O(1).
/// Thread Safety: safe before threads start. Owner: AEC.
/// Since: digit-6 0.1.0.
///
/// Example: `envOr("AAAS_DB_PATH", "/data/digit-6.db")`.
///
/// See Also: ``loadConfig(_:)``.
func envOr(_ name: String, _ fallback: String) -> String {
  guard let raw = getenv(name) else { return fallback }
  let value = String(cString: raw)
  return value.isEmpty ? fallback : value
}

/// Parse a decimal integer within a range.
///
/// Business Justification: invalid configuration stops the start instead
/// of being guessed at.
///
/// - Parameters:
///   - text: Decimal text.
///   - range: Allowed values.
/// - Returns: The value, or nil when `text` is not a plain decimal integer
///   in `range`.
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `parseInt("8080", 1...65535) == 8080`.
///
/// See Also: ``loadConfig(_:)``.
func parseInt(_ text: String, _ range: ClosedRange<Int>) -> Int? {
  guard (1...9).contains(text.count), text.utf8.allSatisfy({ (48...57).contains($0) }),
    let value = Int(text), range.contains(value)
  else { return nil }
  return value
}

/// Read the configuration from the environment.
///
/// Description: `AAAS_BOOTSTRAP` must be env (platform arrives with P5.2);
/// `AAAS_DIGIT` must be 0...9 and `AAAS_HTTP_PORT` 1...65535. Each failure
/// is logged at error level.
///
/// Business Justification: no hard-coded hosts, ports or paths
/// (CLAUDE.md 6.1).
///
/// - Parameter log: Logger for the failures.
/// - Returns: The configuration, or nil when a value is invalid.
///
/// Errors: none (nil). Side Effects: reads the environment; logs failures.
/// Complexity: O(1). Thread Safety: safe before threads start.
/// Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `let config = loadConfig(log)`.
///
/// See Also: ``run()``.
func loadConfig(_ log: Logger) -> Config? {
  let bootstrap = envOr("AAAS_BOOTSTRAP", "env")
  guard bootstrap == "env" else {
    log.write(.error, "unsupported AAAS_BOOTSTRAP; only env exists before P5.2", detail: bootstrap)
    return nil
  }
  guard let digit = parseInt(envOr("AAAS_DIGIT", "6"), 0...9) else {
    log.write(.error, "AAAS_DIGIT must be 0..9", detail: envOr("AAAS_DIGIT", ""))
    return nil
  }
  guard let port = parseInt(envOr("AAAS_HTTP_PORT", "8080"), 1...65535) else {
    log.write(.error, "AAAS_HTTP_PORT must be 1..65535", detail: envOr("AAAS_HTTP_PORT", ""))
    return nil
  }
  return Config(
    digit: digit, port: port, dbPath: envOr("AAAS_DB_PATH", "/data/digit-6.db"),
    migrationsDir: envOr("AAAS_MIGRATIONS_DIR", "/app/migrations"))
}

/// Run the service.
///
/// Description: configuration, database open and migration, digit check,
/// then the server until SIGTERM or SIGINT. Both signals are blocked
/// before any thread starts and awaited with `sigwait`, so no handler runs
/// in signal context.
///
/// Business Justification: the digit-6 process (CLAUDE.md 2, row 19).
///
/// - Returns: The exit status: 0 after a graceful stop, 1 when a start-up
///   check fails.
///
/// Errors: none (status 1). Side Effects: opens the database and a socket;
/// logs; serves HTTP. Complexity: runs until stopped. Thread Safety: call
/// once, on the main thread. Owner: AEC. Since: digit-6 0.1.0.
///
/// Example: `exit(run())`.
///
/// See Also: ``loadConfig(_:)``, ``DigitServer``.
func run() -> Int32 {
  let log = Logger(
    service: envOr("AAAS_SERVICE", "digit-6"),
    threshold: Level.parse(envOr("AAAS_LOG_LEVEL", "info"), fallback: .info))
  guard let config = loadConfig(log) else { return 1 }
  let store: Store
  do {
    store = try Store(path: config.dbPath, log: log)
    try store.migrate(config.migrationsDir)
    guard try store.read().digit == config.digit else {
      log.write(.error, "the database does not hold the configured digit", detail: config.dbPath)
      return 1
    }
  } catch {
    log.write(.error, "the database cannot be prepared", detail: "\(error)")
    return 1
  }

  var signals = sigset_t()
  sigemptyset(&signals)
  sigaddset(&signals, SIGTERM)
  sigaddset(&signals, SIGINT)
  pthread_sigmask(SIG_BLOCK, &signals, nil)

  let api = Api(
    store: store, digit: config.digit,
    metrics: Metrics(digit: config.digit, version: serviceVersion), log: log)
  let server: DigitServer
  do {
    server = try DigitServer(port: config.port, api: api, log: log)
  } catch {
    log.write(.error, "cannot start the HTTP server", detail: "port \(config.port): \(error)")
    return 1
  }
  log.write(
    .info, "listening",
    detail: "port \(config.port), digit \(config.digit), version \(serviceVersion)")
  var received: Int32 = 0
  sigwait(&signals, &received)
  log.write(.info, "shutting down", detail: received == SIGTERM ? "SIGTERM" : "SIGINT")
  server.stop()
  log.write(.info, "stopped")
  return 0
}

exit(run())
