// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/service.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The digit-8 process: configuration, start-up checks, the
//                  HTTP server and the SIGTERM handling.
// Related Docs:    services/digit-8/README.md, CLAUDE.md 4.4 and 6.1,
//                  ADR-0022, ADR-0030

/**
 * The digit-8 process, called by the entry point in `digit8.app`.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.service;

import core.sys.posix.signal : pthread_sigmask, SIG_BLOCK, sigaddset,
    sigemptyset, SIGINT, sigset_t, SIGTERM, sigwait;
import digit8.api : Api;
import digit8.log : Level, Logger, parseLevel;
import digit8.metrics : Metrics;
import digit8.server : DigitServer, ServerException;
import digit8.store : Store, StoreException;
import std.algorithm.searching : all;
import std.ascii : isDigit;
import std.conv : to;
import std.format : format;
import std.process : environment;
import std.typecons : Nullable, nullable;

/// Version of the service (SemVer, docs/CHANGELOG.md).
enum string serviceVersion = "0.1.0";

/**
 * Configuration of the service, read from the environment.
 *
 * Business_Justification: no hard-coded hosts, ports or paths
 * (CLAUDE.md 6.1).
 *
 * Thread_Safety: a value type. Owner: Arithmetic Excellence Center (AEC).
 * Since: digit-8 0.1.0.
 */
struct Config
{
    /// The digit the service represents, 0..9 (`AAAS_DIGIT`).
    int digit;
    /// The HTTP port, 1..65535 (`AAAS_HTTP_PORT`).
    ushort port;
    /// The SQLite file (`AAAS_DB_PATH`).
    string dbPath;
    /// The directory of the migration files (`AAAS_MIGRATIONS_DIR`).
    string migrationsDir;
}

/**
 * An environment variable, or a fallback when it is unset or empty.
 *
 * Business_Justification: configuration comes only from the environment
 * until P5.2 (CLAUDE.md 6.1).
 *
 * Params:
 *   name = the variable name.
 *   fallback = the value used when it is unset or empty.
 * Returns: the value.
 *
 * Errors: none. Side Effects: reads the environment. Complexity: O(1).
 * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
 *
 * See_Also: `loadConfig`.
 */
string envOr(string name, string fallback) @safe
{
    auto value = environment.get(name);
    return value is null || value.length == 0 ? fallback : value;
}

///
unittest
{
    assert(envOr("AAAS_UNIT_TEST_UNSET_VARIABLE", "fallback") == "fallback");
}

/**
 * Parse a decimal integer within a range.
 *
 * Business_Justification: invalid configuration stops the start instead
 * of being guessed at.
 *
 * Params:
 *   text = the decimal text: 1 to 9 ASCII digits.
 *   low = the smallest allowed value.
 *   high = the largest allowed value.
 * Returns: the value, or an empty `Nullable` when `text` is not a plain
 * decimal integer in `low .. high` (both included).
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 *
 * See_Also: `loadConfig`.
 */
Nullable!int parseInt(string text, int low, int high) pure @safe
{
    if (text.length < 1 || text.length > 9 || !text.all!isDigit)
    {
        return Nullable!int.init;
    }
    auto value = text.to!int;
    return value < low || value > high ? Nullable!int.init : nullable(value);
}

///
unittest
{
    assert(parseInt("8080", 1, 65_535).get == 8080);
    assert(parseInt("0", 1, 65_535).isNull);
    assert(parseInt("+8", 0, 9).isNull);
    assert(parseInt("1234567890", 0, int.max).isNull);
}

/**
 * Read the configuration from the environment.
 *
 * Description: `AAAS_BOOTSTRAP` must be env (platform arrives with P5.2);
 * `AAAS_DIGIT` must be 0..9 and `AAAS_HTTP_PORT` 1..65535. Each failure is
 * logged at error level.
 *
 * Business_Justification: no hard-coded hosts, ports or paths
 * (CLAUDE.md 6.1).
 *
 * Params:
 *   log = the logger for the failures.
 * Returns: the configuration, or an empty `Nullable` when a value is
 * invalid.
 *
 * Errors: none (empty result). Side Effects: reads the environment; logs
 * failures. Complexity: O(1). Thread Safety: safe. Owner: AEC.
 * Since: digit-8 0.1.0.
 *
 * See_Also: `run`.
 */
Nullable!Config loadConfig(Logger log) @safe
{
    auto bootstrap = envOr("AAAS_BOOTSTRAP", "env");
    if (bootstrap != "env")
    {
        log.write(Level.error,
                "unsupported AAAS_BOOTSTRAP; only env exists before P5.2", bootstrap);
        return Nullable!Config.init;
    }
    auto digit = parseInt(envOr("AAAS_DIGIT", "8"), 0, 9);
    if (digit.isNull)
    {
        log.write(Level.error, "AAAS_DIGIT must be 0..9", envOr("AAAS_DIGIT", ""));
        return Nullable!Config.init;
    }
    auto port = parseInt(envOr("AAAS_HTTP_PORT", "8080"), 1, 65_535);
    if (port.isNull)
    {
        log.write(Level.error, "AAAS_HTTP_PORT must be 1..65535", envOr("AAAS_HTTP_PORT", ""));
        return Nullable!Config.init;
    }
    return nullable(Config(digit.get, cast(ushort) port.get, envOr("AAAS_DB_PATH",
            "/data/digit-8.db"), envOr("AAAS_MIGRATIONS_DIR", "/app/migrations")));
}

/**
 * Run the service.
 *
 * Description: configuration, database open and migration, digit check,
 * then the server until SIGTERM or SIGINT. Both signals are blocked before
 * any thread starts and awaited with `sigwait`, so no handler runs in
 * signal context.
 *
 * Business_Justification: the digit-8 process (CLAUDE.md 2, row 21).
 *
 * Returns: the exit status: 0 after a graceful stop, 1 when a start-up
 * check fails.
 *
 * Errors: none (status 1). Side Effects: opens the database and a socket;
 * logs; serves HTTP. Complexity: runs until stopped. Thread Safety: call
 * once, on the main thread. Owner: AEC. Since: digit-8 0.1.0.
 *
 * See_Also: `loadConfig`, `digit8.server.DigitServer`.
 */
int run() @trusted
{
    auto log = new Logger(envOr("AAAS_SERVICE", "digit-8"),
            parseLevel(envOr("AAAS_LOG_LEVEL", "info"), Level.info));
    auto loaded = loadConfig(log);
    if (loaded.isNull)
    {
        return 1;
    }
    auto config = loaded.get;
    Store store;
    try
    {
        store = new Store(config.dbPath, log);
        store.migrate(config.migrationsDir);
        if (store.read().digit != config.digit)
        {
            log.write(Level.error,
                    "the database does not hold the configured digit", config.dbPath);
            return 1;
        }
    }
    catch (StoreException error)
    {
        log.write(Level.error, "the database cannot be prepared", error.msg);
        return 1;
    }

    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGTERM);
    sigaddset(&signals, SIGINT);
    pthread_sigmask(SIG_BLOCK, &signals, null);

    auto api = new Api(store, config.digit, new Metrics(config.digit, serviceVersion), log);
    DigitServer server;
    try
    {
        server = new DigitServer(config.port, api, log);
    }
    catch (ServerException error)
    {
        log.write(Level.error, "cannot start the HTTP server",
                format!"port %d: %s"(config.port, error.msg));
        return 1;
    }
    log.write(Level.info, "listening",
            format!"port %d, digit %d, version %s"(config.port, config.digit, serviceVersion));
    int received;
    sigwait(&signals, &received);
    log.write(Level.info, "shutting down", received == SIGTERM ? "SIGTERM" : "SIGINT");
    server.stop();
    log.write(Level.info, "stopped");
    return 0;
}
