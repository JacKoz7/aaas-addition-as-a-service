// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/log.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Structured JSON log lines on stdout with the fields of
//                  CLAUDE.md 6.1 (ts, level, service, msg, taskId, traceId,
//                  spanId).
// Related Docs:    services/digit-8/README.md, CLAUDE.md 6.1, ADR-0030

/**
 * Structured logging of the digit-8 service.
 *
 * Every line is one JSON object written with a single `write(2)` call on
 * descriptor 1, so lines of concurrent connection threads never
 * interleave. The digit service has no task, so `taskId` is always `null`.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.log;

import core.stdc.errno : EINTR, errno;
import core.sys.posix.unistd : posixWrite = write;
import std.array : appender;
import std.datetime.systime : Clock, SysTime;
import std.datetime.timezone : UTC;
import std.format : format;

/**
 * Severity of a log line, from the most verbose to the most severe.
 *
 * Business_Justification: operators filter the log stream by level
 * (`AAAS_LOG_LEVEL`); request lines are written at `debug_` only.
 *
 * Thread_Safety: a value type. Owner: Arithmetic Excellence Center (AEC).
 * Since: digit-8 0.1.0.
 */
enum Level
{
    /// Per-request detail (`request answered`, `request rejected`).
    debug_,
    /// Lifecycle events: migrations, listening, shutting down, stopped.
    info,
    /// Degraded but serving: connection limit reached, accept failed.
    warn,
    /// A failure: the database cannot be read, a start-up check failed.
    error,
}

/**
 * The name of a level as written in the `level` field.
 *
 * Params:
 *   level = any level.
 * Returns: `debug`, `info`, `warn` or `error`.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
string levelName(Level level) pure nothrow @safe
{
    final switch (level)
    {
    case Level.debug_:
        return "debug";
    case Level.info:
        return "info";
    case Level.warn:
        return "warn";
    case Level.error:
        return "error";
    }
}

///
unittest
{
    assert(levelName(Level.warn) == "warn");
    assert(levelName(Level.debug_) == "debug");
}

/**
 * Parse a level name, falling back for an unknown or empty name.
 *
 * Business_Justification: a mistyped `AAAS_LOG_LEVEL` must not stop the
 * service; it logs at the fallback level instead.
 *
 * Params:
 *   name = the configured name (lower case).
 *   fallback = the level used when `name` is not one of the four names.
 * Returns: the level.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
Level parseLevel(string name, Level fallback) pure nothrow @safe
{
    foreach (level; [Level.debug_, Level.info, Level.warn, Level.error])
    {
        if (levelName(level) == name)
        {
            return level;
        }
    }
    return fallback;
}

///
unittest
{
    assert(parseLevel("debug", Level.info) == Level.debug_);
    assert(parseLevel("verbose", Level.info) == Level.info);
}

/**
 * Escape a string for a JSON string literal (RFC 8259).
 *
 * Description: escapes `"` and `\`, writes `\n`, `\r` and `\t` in short
 * form and every other control character below U+0020 as `\u00XX`. Other
 * bytes, UTF-8 sequences included, are copied unchanged.
 *
 * Business_Justification: a log line or problem detail that quotes a value
 * must stay valid JSON whatever the value holds.
 *
 * Params:
 *   text = any string.
 * Returns: the escaped text, without the surrounding quotes.
 *
 * Errors: none. Side Effects: none. Complexity: O(n) time and memory.
 * Thread Safety: pure. Owner: AEC. Since: digit-8 0.1.0.
 */
string jsonEscape(string text) pure @safe
{
    auto result = appender!string();
    foreach (char c; text)
    {
        switch (c)
        {
        case '"':
            result ~= `\"`;
            break;
        case '\\':
            result ~= `\\`;
            break;
        case '\n':
            result ~= `\n`;
            break;
        case '\r':
            result ~= `\r`;
            break;
        case '\t':
            result ~= `\t`;
            break;
        default:
            if (c < 0x20)
            {
                result ~= format!`\u%04x`(c);
            }
            else
            {
                result ~= c;
            }
        }
    }
    return result[];
}

///
unittest
{
    assert(jsonEscape(`a"b\c`) == `a\"b\\c`);
    assert(jsonEscape("tab\there\x01") == `tab\there\u0001`);
    assert(jsonEscape("zażółć") == "zażółć");
}

/**
 * A JSON string literal, or `null` for an absent value.
 *
 * Params:
 *   value = the text; `null` (the D null string) when absent.
 * Returns: `"…"` or `null`.
 *
 * Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
private string quoted(string value) pure @safe
{
    return value is null ? "null" : `"` ~ jsonEscape(value) ~ `"`;
}

///
unittest
{
    assert(quoted(null) == "null");
    assert(quoted("") == `""`);
}

/**
 * The current UTC time in RFC 3339 with milliseconds.
 *
 * Business_Justification: the `ts` field must be comparable across the 35
 * services; every service writes UTC with a `Z` suffix.
 *
 * Returns: for example `2026-10-24T19:52:01.123Z`.
 *
 * Errors: none. Side Effects: reads the clock. Complexity: O(1).
 * Thread Safety: safe. Owner: AEC. Since: digit-8 0.1.0.
 */
string timestamp() @safe
{
    return formatTimestamp(Clock.currTime(UTC()));
}

/**
 * Format a time as RFC 3339 UTC with milliseconds.
 *
 * Params:
 *   time = any time; it is converted to UTC.
 * Returns: `YYYY-MM-DDTHH:MM:SS.mmmZ`.
 *
 * Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
string formatTimestamp(SysTime time) @safe
{
    auto utc = time.toUTC();
    return format!"%04d-%02d-%02dT%02d:%02d:%02d.%03dZ"(utc.year, utc.month,
            utc.day, utc.hour, utc.minute, utc.second, utc.fracSecs.total!"msecs");
}

///
unittest
{
    import core.time : msecs;
    import std.datetime.date : DateTime;

    auto time = SysTime(DateTime(2026, 10, 24, 19, 52, 1), 123.msecs, UTC());
    assert(formatTimestamp(time) == "2026-10-24T19:52:01.123Z");
}

/**
 * A logger bound to one service name and a threshold.
 *
 * Description: `sink` replaces stdout when set (the tests capture lines
 * with it); lines below `threshold` are dropped.
 *
 * Thread_Safety: immutable after construction; `write` may be called from
 * any thread when the sink is thread-safe (stdout is).
 * Owner: Arithmetic Excellence Center (AEC). Since: digit-8 0.1.0.
 */
final class Logger
{
    /// Service name written in the `service` field.
    immutable string service;
    /// Lowest level written.
    immutable Level threshold;
    /// Receives each line instead of stdout when set (without newline).
    private void delegate(string) sink;

    /**
     * Create a logger.
     *
     * Params:
     *   service = the service name, for example `digit-8`.
     *   threshold = the lowest level written.
     *   sink = receives each line instead of stdout; `null` for stdout.
     *
     * Errors: none. Side Effects: none. Complexity: O(1).
     * Thread Safety: not applicable. Owner: AEC. Since: digit-8 0.1.0.
     */
    this(string service, Level threshold, void delegate(string) sink = null) @safe
    {
        this.service = service;
        this.threshold = threshold;
        this.sink = sink;
    }

    /**
     * Format one log line without writing it.
     *
     * Description: the fields are `ts`, `level`, `service`, `msg`, `taskId`
     * (always `null`), `traceId`, `spanId` and, when given, `detail`.
     *
     * Params:
     *   level = severity.
     *   msg = fixed message.
     *   detail = variable detail; `null` when none.
     *   traceId = the caller's trace identifier; `null` when none.
     *   spanId = the caller's span identifier; `null` when none.
     * Returns: the JSON object, without a newline.
     *
     * Errors: none. Side Effects: reads the clock. Complexity: O(n) in the
     * length of the fields. Thread Safety: safe. Owner: AEC.
     * Since: digit-8 0.1.0.
     */
    string format(Level level, string msg, string detail = null,
            string traceId = null, string spanId = null) const @safe
    {
        auto line = appender!string();
        line ~= `{"ts":"` ~ timestamp() ~ `","level":"` ~ levelName(level) ~ `"`;
        line ~= `,"service":` ~ quoted(service) ~ `,"msg":` ~ quoted(msg);
        line ~= `,"taskId":null,"traceId":` ~ quoted(traceId) ~ `,"spanId":` ~ quoted(spanId);
        if (detail !is null)
        {
            line ~= `,"detail":` ~ quoted(detail);
        }
        line ~= "}";
        return line[];
    }

    /**
     * Write one log line if its level reaches the threshold.
     *
     * Description: the line goes to the sink when one is set, otherwise to
     * stdout followed by a newline, in one `write(2)` call (repeated only
     * for a partial write).
     *
     * Params:
     *   level = severity.
     *   msg = fixed message.
     *   detail = variable detail; `null` when none.
     *   traceId = the caller's trace identifier; `null` when none.
     *   spanId = the caller's span identifier; `null` when none.
     *
     * Errors: none (a failed write to stdout is ignored). Side Effects:
     * writes to stdout or calls the sink. Complexity: O(n) in the length of
     * the fields. Thread Safety: safe from any thread. Owner: AEC.
     * Since: digit-8 0.1.0.
     *
     * Examples: `log.write(Level.info, "listening", "port 8080");`
     *
     * See_Also: `format`.
     */
    void write(Level level, string msg, string detail = null,
            string traceId = null, string spanId = null) const @trusted
    {
        if (level < threshold)
        {
            return;
        }
        auto line = format(level, msg, detail, traceId, spanId);
        if (sink !is null)
        {
            sink(line);
            return;
        }
        writeAll(line ~ "\n");
    }
}

///
unittest
{
    string[] lines;
    auto log = new Logger("digit-8", Level.info, (string line) { lines ~= line; });
    log.write(Level.debug_, "dropped");
    log.write(Level.info, "kept", "a\"b");
    import std.algorithm.searching : endsWith;

    assert(lines.length == 1);
    assert(lines[0].endsWith(
            `"msg":"kept","taskId":null,"traceId":null,"spanId":null,"detail":"a\"b"}`));
}

/**
 * Write all bytes to descriptor 1.
 *
 * Description: repeats `write(2)` after a partial write or `EINTR`; stops
 * at any other error.
 *
 * Params:
 *   text = the bytes.
 *
 * Errors: none (errors are ignored: logging must never stop the service).
 * Side Effects: writes stdout. Complexity: O(n). Thread Safety: safe; a
 * line up to `PIPE_BUF` (4096) bytes is written atomically.
 * Owner: AEC. Since: digit-8 0.1.0.
 */
private void writeAll(string text) @trusted nothrow @nogc
{
    size_t offset = 0;
    while (offset < text.length)
    {
        auto count = posixWrite(1, text.ptr + offset, text.length - offset);
        if (count < 0 && errno == EINTR)
        {
            continue;
        }
        if (count <= 0)
        {
            return;
        }
        offset += count;
    }
}
