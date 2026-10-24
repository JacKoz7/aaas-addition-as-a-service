// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          tests/digit8_tests/support.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Shared fixtures of the unit tests: a migrated in-memory
//                  database, a contract over it, an in-memory connection
//                  and helpers that read replies.
// Related Docs:    services/digit-8/README.md, ADR-0030

/**
 * Fixtures of the digit-8 unit tests.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8_tests.support;

import core.sync.mutex : Mutex;
import digit8.api : Api, Reply;
import digit8.http : Connection, serveConnection;
import digit8.log : Level, Logger;
import digit8.metrics : Metrics;
import digit8.store : Store;
import std.algorithm.iteration : map;
import std.array : array, split;
import std.conv : to;
import std.path : buildNormalizedPath, dirName;
import std.regex : matchAll, regex;

/// The service's migrations directory, found from this file's location.
enum string migrationsDir = buildNormalizedPath(dirName(__FILE_FULL_PATH__),
            "..", "..", "migrations");

/**
 * Collects log lines from any thread (a logger sink for the tests).
 *
 * Thread_Safety: safe; the lines are guarded by a mutex.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
final class Capture
{
    /// Guards `captured`.
    private Mutex lock;
    /// The lines received so far.
    private string[] captured;

    /**
     * Create an empty capture.
     *
     * Errors: none. Side Effects: none. Complexity: O(1).
     * Thread Safety: not applicable. Owner: AEC. Since: digit-8 0.1.0.
     */
    this() @trusted
    {
        lock = new Mutex();
    }

    /**
     * Append one line (the sink).
     *
     * Params:
     *   line = the log line.
     *
     * Errors: none. Side Effects: stores the line. Complexity: O(1)
     * amortised. Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    void append(string line) @trusted
    {
        lock.lock();
        scope (exit)
            lock.unlock();
        captured ~= line;
    }

    /**
     * The lines received so far.
     *
     * Returns: a copy of the lines.
     *
     * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety:
     * safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    string[] lines() @trusted
    {
        lock.lock();
        scope (exit)
            lock.unlock();
        return captured.dup;
    }

    /**
     * A logger writing into this capture.
     *
     * Params:
     *   threshold = the lowest level kept.
     * Returns: the logger.
     *
     * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
     * safe. Owner: AEC. Since: digit-8 0.1.0.
     */
    Logger logger(Level threshold = Level.debug_) @safe
    {
        return new Logger("digit-8", threshold, &append);
    }
}

/**
 * A logger that drops every line below `error` into a fresh capture.
 *
 * Returns: the logger.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
Logger quietLogger() @safe
{
    return new Capture().logger(Level.error);
}

/**
 * An in-memory database with the service's migrations applied.
 *
 * Returns: the store.
 *
 * Errors: a `StoreException` fails the test. Side Effects: none outside
 * the process. Complexity: O(s) in the migrations. Thread Safety: one
 * test. Owner: AEC. Since: digit-8 0.1.0.
 */
Store migrated() @safe
{
    auto store = new Store(":memory:", quietLogger());
    store.migrate(migrationsDir);
    return store;
}

/**
 * The parts of a contract over a migrated in-memory database.
 *
 * Thread_Safety: one test. Owner: AEC. Since: digit-8 0.1.0.
 */
struct Fixture
{
    /// The contract for digit 8.
    Api api;
    /// Its database.
    Store store;
    /// Its counters.
    Metrics metrics;
    /// The log lines it wrote.
    Capture capture;
}

/**
 * A contract for digit 8 over a migrated in-memory database.
 *
 * Params:
 *   digit = the configured digit (8 matches the seed).
 * Returns: the contract and its parts.
 *
 * Errors: a `StoreException` fails the test. Side Effects: none outside
 * the process. Complexity: O(s). Thread Safety: one test. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
Fixture contract(int digit = 8) @safe
{
    auto store = migrated();
    auto metrics = new Metrics(digit, "0.1.0");
    auto capture = new Capture();
    return Fixture(new Api(store, digit, metrics, capture.logger()), store, metrics, capture);
}

/**
 * An in-memory connection: the input arrives in the given chunks, one per
 * receive; the output is collected.
 *
 * Thread_Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
 */
final class FakeConnection : Connection
{
    /// Chunks not received yet.
    private string[] chunks;
    /// Everything sent.
    string output;

    /**
     * Create a connection with the given input.
     *
     * Params:
     *   chunks = the input, one receive per chunk.
     *
     * Errors: none. Side Effects: none. Complexity: O(1).
     * Thread Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    this(string[] chunks) pure nothrow @safe
    {
        this.chunks = chunks;
    }

    /**
     * Receive the next chunk, or as much of it as fits.
     *
     * Params:
     *   buffer = where the bytes go.
     * Returns: the count; 0 when the input is exhausted.
     *
     * Errors: none. Side Effects: consumes input. Complexity: O(n).
     * Thread Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    size_t receive(ubyte[] buffer) @safe
    {
        import std.algorithm.comparison : min;

        while (chunks.length > 0 && chunks[0].length == 0)
        {
            chunks = chunks[1 .. $];
        }
        if (chunks.length == 0)
        {
            return 0;
        }
        auto count = min(buffer.length, chunks[0].length);
        buffer[0 .. count] = cast(const(ubyte)[]) chunks[0][0 .. count];
        chunks[0] = chunks[0][count .. $];
        return count;
    }

    /**
     * Collect the bytes.
     *
     * Params:
     *   bytes = the bytes.
     * Returns: true.
     *
     * Errors: none. Side Effects: appends to `output`. Complexity: O(n).
     * Thread Safety: one thread. Owner: AEC. Since: digit-8 0.1.0.
     */
    bool send(const(ubyte)[] bytes) @safe
    {
        output ~= cast(const(char)[]) bytes;
        return true;
    }
}

/**
 * Serve the given input with the contract for digit 8 and return the
 * output.
 *
 * Params:
 *   chunks = the input, one receive per chunk.
 * Returns: everything the server sent.
 *
 * Errors: none. Side Effects: none outside the process. Complexity: O(n).
 * Thread Safety: one test. Owner: AEC. Since: digit-8 0.1.0.
 */
string serve(string[] chunks...) @safe
{
    auto fixture = contract();
    auto connection = new FakeConnection(chunks.dup);
    serveOn(connection, fixture.api, fixture.capture.logger());
    return connection.output;
}

/**
 * Serve a connection with a contract until its input ends, without a
 * stop and without busy notifications.
 *
 * Params:
 *   connection = the connection.
 *   api = the contract.
 *   log = the logger of the request lines.
 *
 * Errors: none. Side Effects: reads and writes the connection.
 * Complexity: O(n). Thread Safety: one test. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
void serveOn(Connection connection, Api api, Logger log) @safe
{
    serveConnection(connection, &api.handle, () => false, (bool) {}, log);
}

/**
 * The status codes of the replies in an output, in order.
 *
 * Params:
 *   output = the bytes a server sent.
 * Returns: the status codes.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
int[] statuses(string output) @safe
{
    return output.matchAll(regex(`HTTP/1\.1 (\d{3}) `)).map!(m => m[1].to!int).array;
}
