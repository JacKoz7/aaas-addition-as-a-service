// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          tests/digit8_tests/contract_test.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Unit tests of the database and the digit contract
//                  against the real migrations: migration runner, row
//                  checks, replies, problem details and counters.
// Related Docs:    contracts/http/digit.yaml, migrations/0001_digit.sql,
//                  ADR-0022

/**
 * Tests of `digit8.store` and `digit8.api`.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8_tests.contract_test;

import digit8.api : jsonType, problemType, prometheusType;
import digit8.metrics : Endpoint, Outcome;
import digit8.store : DigitRow, Store, StoreException;
import digit8_tests.support;
import std.algorithm.searching : canFind;
import std.exception : assertThrown, collectExceptionMsg;
import std.file : mkdirRecurse, rmdirRecurse, tempDir, write;
import std.path : buildPath;

// The migrations apply once: a second run applies nothing.
unittest
{
    auto store = new Store(":memory:", quietLogger());
    assert(store.migrate(migrationsDir) == 1);
    assert(store.migrate(migrationsDir) == 0);
    assert(store.isApplied("0001_digit.sql"));
    assert(!store.isApplied("0002_missing.sql"));
}

// The seed holds digit 8: value 8, successor 9, no carry.
unittest
{
    assert(migrated().read() == DigitRow(8, 8, 9, false));
}

// A missing migrations directory fails with its path.
unittest
{
    auto store = new Store(":memory:", quietLogger());
    auto message = collectExceptionMsg!StoreException(store.migrate("/nonexistent/migrations"));
    assert(message == "cannot read the migrations directory /nonexistent/migrations");
}

// A failing migration is rolled back and not recorded; the earlier one
// stays applied.
unittest
{
    auto dir = buildPath(tempDir, "digit8-migrations-test");
    mkdirRecurse(dir);
    scope (exit)
        rmdirRecurse(dir);
    write(buildPath(dir, "0001_a.sql"), "CREATE TABLE a (x INTEGER) STRICT;");
    write(buildPath(dir, "0002_b.sql"),
            "CREATE TABLE b (x INTEGER); INSERT INTO nowhere VALUES (1);");
    write(buildPath(dir, ".0003_hidden.sql"), "garbage");
    write(buildPath(dir, "notes.txt"), "garbage");
    auto store = new Store(":memory:", quietLogger());
    auto message = collectExceptionMsg!StoreException(store.migrate(dir));
    assert(message.canFind("migration 0002_b.sql failed: no such table: nowhere"));
    assert(store.isApplied("0001_a.sql"));
    assert(!store.isApplied("0002_b.sql"));
    store.execute("INSERT INTO a VALUES (1);");
    assertThrown!StoreException(store.execute("SELECT * FROM b;"));
}

// The digit table must hold exactly one row.
unittest
{
    auto store = migrated();
    store.execute("INSERT INTO digit VALUES (9, 9, 0, 1);");
    assert(collectExceptionMsg!StoreException(
            store.read()) == "the table digit holds more than one row");
    store.execute("DELETE FROM digit;");
    assert(collectExceptionMsg!StoreException(store.read()) == "the table digit holds no row");
}

// A database that cannot be opened fails with the SQLite message.
unittest
{
    auto message = collectExceptionMsg!StoreException(new Store("/nonexistent/dir/d.db",
            quietLogger()));
    assert(message == "cannot open the database: unable to open database file");
}

// GET /value and GET /next answer the seeded row as JSON.
unittest
{
    auto fixture = contract();
    auto value = fixture.api.handle("GET", "/value");
    assert(value.status == 200 && value.contentType == jsonType);
    assert(value.body == `{"digit":8,"value":8}`);
    auto next = fixture.api.handle("GET", "/next");
    assert(next.status == 200 && next.body == `{"digit":8,"next":9,"carry":false}`);
}

// The replies come from the database on every request, not from code.
unittest
{
    auto fixture = contract();
    fixture.store.execute("UPDATE digit SET next = 0, carry = 1;");
    assert(fixture.api.handle("GET", "/next").body == `{"digit":8,"next":0,"carry":true}`);
}

// GET /health reports the database check.
unittest
{
    auto fixture = contract();
    auto healthy = fixture.api.handle("GET", "/health");
    assert(healthy.status == 200 && healthy.contentType == jsonType);
    assert(healthy.body == `{"status":"ok","checks":{"database":"ok"}}`);
    fixture.store.execute("DROP TABLE digit;");
    auto unhealthy = fixture.api.handle("GET", "/health");
    assert(unhealthy.status == 503);
    assert(unhealthy.body == `{"status":"error","checks":{"database":"error"}}`);
}

// A database failure answers 503 problem details, counts an error and
// logs the SQLite message.
unittest
{
    auto fixture = contract();
    fixture.store.execute("DROP TABLE digit;");
    auto reply = fixture.api.handle("GET", "/value");
    assert(reply.status == 503 && reply.contentType == problemType);
    assert(reply.body.canFind(`"title":"Service Unavailable","status":503`));
    assert(fixture.metrics.get(Endpoint.value, Outcome.error) == 1);
    assert(fixture.metrics.get(Endpoint.value, Outcome.ok) == 0);
    auto lines = fixture.capture.lines();
    assert(lines.length == 1 && lines[0].canFind(`"level":"error"`));
    assert(lines[0].canFind(`"detail":"no such table: digit"`));
}

// A database holding another digit is refused.
unittest
{
    auto fixture = contract(5);
    assert(fixture.api.handle("GET", "/next").status == 503);
    assert(fixture.api.handle("GET", "/health").status == 503);
    assert(fixture.capture.lines()[0].canFind("the database holds another digit"));
}

// Unknown paths answer 404, other methods 405 with Allow: GET.
unittest
{
    auto fixture = contract();
    auto missing = fixture.api.handle("GET", "/");
    assert(missing.status == 404 && missing.contentType == problemType && missing.allow is null);
    assert(fixture.api.handle("POST", "/nope").status == 404);
    foreach (path; ["/value", "/next", "/health", "/metrics"])
    {
        auto reply = fixture.api.handle("POST", path);
        assert(reply.status == 405 && reply.allow == "GET");
    }
    assert(fixture.api.handle("get", "/value").status == 405);
}

// GET /metrics exposes the counters of the answered requests.
unittest
{
    auto fixture = contract();
    fixture.api.handle("GET", "/value");
    fixture.api.handle("GET", "/next");
    fixture.api.handle("GET", "/next");
    fixture.api.handle("GET", "/health");
    auto reply = fixture.api.handle("GET", "/metrics");
    assert(reply.status == 200 && reply.contentType == prometheusType);
    assert(reply.body.canFind(`digit_requests_total{digit="8",endpoint="value",outcome="ok"} 1`));
    assert(reply.body.canFind(`digit_requests_total{digit="8",endpoint="next",outcome="ok"} 2`));
    assert(reply.body.canFind(`digit_requests_total{digit="8",endpoint="next",outcome="error"} 0`));
    assert(reply.body.canFind(`# TYPE digit_build_info gauge`));
}
