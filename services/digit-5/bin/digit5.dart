// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          bin/digit5.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Entry point of the digit-5 service: configuration,
//                  start-up checks, the HTTP server and the SIGTERM
//                  handling.
// Related Docs:    services/digit-5/README.md, CLAUDE.md 4.4 and 6.1,
//                  ADR-0022, ADR-0027

/// Entry point of the digit-5 service.
///
/// Reads the configuration from the environment (AAAS_BOOTSTRAP=env, the
/// only mode before P5.2), opens and migrates the database, checks that it
/// holds the configured digit, serves HTTP on AAAS_HTTP_PORT and stops on
/// SIGTERM or SIGINT. Exits with status 1 when any start-up check fails.
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

import 'dart:async';
import 'dart:io';

import 'package:digit_service/digit_service.dart';

/// Version of the service (SemVer, docs/CHANGELOG.md).
///
/// Owner: AEC. Since: digit-5 0.1.0.
const String serviceVersion = '0.1.0';

/// Configuration of the service, read from the environment.
///
/// Business Justification: no hard-coded hosts, ports or paths
/// (CLAUDE.md 6.1).
///
/// Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
/// Since: digit-5 0.1.0.
typedef Config = ({int digit, int port, String dbPath, String migrationsDir});

/// An environment variable, or a fallback when it is unset or empty.
///
/// Business Justification: configuration comes only from the environment
/// until P5.2 (CLAUDE.md 6.1).
///
/// Parameters:
/// - [name]: variable name.
/// - [fallback]: value used when unset or empty.
///
/// Returns: the value.
///
/// Errors: none. Side Effects: reads the environment. Complexity: O(1).
/// Thread Safety: safe. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `envOr('AAAS_DB_PATH', '/data/digit-5.db')`.
///
/// See Also: [loadConfig].
String envOr(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

/// Parse a decimal integer within a range.
///
/// Business Justification: invalid configuration stops the start instead
/// of being guessed at.
///
/// Parameters:
/// - [text]: decimal text.
/// - [min]: smallest allowed value.
/// - [max]: largest allowed value.
///
/// Returns: the value, or null when [text] is not a plain decimal integer
/// in [[min], [max]].
///
/// Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
/// safe. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `parseInt('8080', 1, 65535) == 8080`.
///
/// See Also: [loadConfig].
int? parseInt(String text, int min, int max) {
  if (!RegExp(r'^\d{1,9}$').hasMatch(text)) {
    return null;
  }
  final value = int.parse(text);
  return value < min || value > max ? null : value;
}

/// Read the configuration from the environment.
///
/// Description: AAAS_BOOTSTRAP must be env (platform arrives with P5.2);
/// AAAS_DIGIT must be 0..9 and AAAS_HTTP_PORT 1..65535. Each failure is
/// logged at error level.
///
/// Business Justification: no hard-coded hosts, ports or paths
/// (CLAUDE.md 6.1).
///
/// Parameters:
/// - [log]: logger for the failures.
///
/// Returns: the configuration, or null when a value is invalid.
///
/// Errors: none (null on failure). Side Effects: reads the environment;
/// logs failures. Complexity: O(1). Thread Safety: safe. Owner: AEC.
/// Since: digit-5 0.1.0.
///
/// Example: `final config = loadConfig(log);`
///
/// See Also: [main].
Config? loadConfig(Logger log) {
  final bootstrap = envOr('AAAS_BOOTSTRAP', 'env');
  if (bootstrap != 'env') {
    log.write(
      Level.error,
      'unsupported AAAS_BOOTSTRAP; only env exists before P5.2',
      detail: bootstrap,
    );
    return null;
  }
  final digit = parseInt(envOr('AAAS_DIGIT', '5'), 0, 9);
  if (digit == null) {
    log.write(
      Level.error,
      'AAAS_DIGIT must be 0..9',
      detail: Platform.environment['AAAS_DIGIT'],
    );
    return null;
  }
  final port = parseInt(envOr('AAAS_HTTP_PORT', '8080'), 1, 65535);
  if (port == null) {
    log.write(
      Level.error,
      'AAAS_HTTP_PORT must be 1..65535',
      detail: Platform.environment['AAAS_HTTP_PORT'],
    );
    return null;
  }
  return (
    digit: digit,
    port: port,
    dbPath: envOr('AAAS_DB_PATH', '/data/digit-5.db'),
    migrationsDir: envOr('AAAS_MIGRATIONS_DIR', '/app/migrations'),
  );
}

/// Open and migrate the database and check that it holds the digit.
///
/// Business Justification: a service must never start for another digit
/// (CLAUDE.md 4.4).
///
/// Parameters:
/// - [config]: the configuration.
/// - [log]: logger.
///
/// Returns: the open store, or null when a check fails (logged).
///
/// Errors: none (null on failure). Side Effects: opens, migrates and reads
/// the database; logs. Complexity: O(migrations). Thread Safety: call once.
/// Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `final store = prepareStore(config, log);`
///
/// See Also: [Store.migrate].
Store? prepareStore(Config config, Logger log) {
  Store? store;
  try {
    store = Store.open(config.dbPath, log)..migrate(config.migrationsDir);
    if (store.read().digit == config.digit) {
      return store;
    }
    log.write(
      Level.error,
      'the database does not hold the configured digit',
      detail: config.dbPath,
    );
  } on StoreException catch (e) {
    log.write(
      Level.error,
      'the database cannot be prepared',
      detail: e.message,
    );
  }
  store?.close();
  return null;
}

/// Run the service.
///
/// Description: configuration, database, then the server until SIGTERM or
/// SIGINT; sets the exit code to 1 when a start-up check fails.
///
/// Business Justification: the digit-5 process (CLAUDE.md 2, row 18).
///
/// Returns: completes when the service has stopped.
///
/// Errors: none (exit code 1 on start-up failures). Side Effects: opens
/// the database and a socket; logs; serves HTTP. Complexity: runs until
/// stopped. Thread Safety: call once. Owner: AEC. Since: digit-5 0.1.0.
///
/// Example: `dart run bin/digit5.dart`.
///
/// See Also: [loadConfig], [DigitServer].
Future<void> main() async {
  final log = Logger(
    envOr('AAAS_SERVICE', 'digit-5'),
    Level.parse(Platform.environment['AAAS_LOG_LEVEL'], Level.info),
  );
  final config = loadConfig(log);
  final store = config == null ? null : prepareStore(config, log);
  if (config == null || store == null) {
    exitCode = 1;
    return;
  }
  final api = Api(
    store,
    config.digit,
    Metrics(config.digit, serviceVersion),
    log,
  );
  final DigitServer server;
  try {
    server = await DigitServer.bind(config.port, api, log);
  } on SocketException catch (e) {
    log.write(
      Level.error,
      'cannot start the HTTP server',
      detail: 'port ${config.port}: ${e.osError?.message ?? e.message}',
    );
    store.close();
    exitCode = 1;
    return;
  }
  log.write(
    Level.info,
    'listening',
    detail:
        'port ${config.port}, digit ${config.digit}, version $serviceVersion',
  );
  final stopRequested = Completer<ProcessSignal>();
  final subscriptions = [
    for (final watched in [ProcessSignal.sigterm, ProcessSignal.sigint])
      watched.watch().listen((received) {
        if (!stopRequested.isCompleted) {
          stopRequested.complete(received);
        }
      }),
  ];
  final signal = await stopRequested.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  log.write(Level.info, 'shutting down', detail: signal.name);
  await server.stop();
  store.close();
  log.write(Level.info, 'stopped');
}
