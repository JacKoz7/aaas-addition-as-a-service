// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          src/DigitLog.pas
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Structured JSON logging on stdout with the fields of
//                  CLAUDE.md 6.1, and JSON string escaping.
// Related Docs:    CLAUDE.md 6.1, services/digit-3/README.md, ADR-0022

{ Structured JSON logs (one object per line on stdout).

  Every line has ts, level, service, msg, taskId, traceId and spanId
  (CLAUDE.md 6.1), plus detail when given. A digit call carries no task, so
  taskId is always null; traceId and spanId come from the caller's
  traceparent header.

  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
unit DigitLog;

{$MODE objfpc}
{$H+}

interface

type

  { Severity of a log line, in increasing order; llOff is a threshold only
    (used by the unit tests) and writes nothing. }
  TLogLevel = (llDebug, llInfo, llWarn, llError, llOff);

{ Configure the service name and the minimum level written.

  Description: lines below Threshold are dropped. Until called, the service
  name is digit and the threshold is llInfo.

  Business Justification: every line names its service; the level is
  configurable per environment (AAAS_LOG_LEVEL).

  @param(Service service name, for example digit-3)
  @param(Threshold minimum level written)

  Errors: none. Side Effects: sets process-wide logging state.
  Complexity: O(1). Thread Safety: safe (guarded by the logging lock).
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: LogInit('digit-3', llInfo).
  See Also: LogWrite. }
procedure LogInit(const Service: string; Threshold: TLogLevel);

{ Parse a level name (debug, info, warn, error).

  Description: case-sensitive; any other value, including an empty string
  (variable unset), yields Fallback.

  Business Justification: the level comes from AAAS_LOG_LEVEL.

  @param(Name level name or an empty string)
  @param(Fallback level returned for unknown names)
  @returns(the parsed level)

  Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: ParseLevel('debug', llInfo) = llDebug.
  See Also: LogInit. }
function ParseLevel(const Name: string; Fallback: TLogLevel): TLogLevel;

{ Escape a string for the inside of a JSON string literal.

  Description: escapes the double quote and the backslash with a backslash,
  newline, carriage return and tab by their short escapes, and the other
  control characters as a u00XX escape (lower-case hex).

  Business Justification: log messages and problem details may contain
  arbitrary text.

  @param(Text text to escape)
  @returns(the escaped text, without surrounding quotes)

  Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: JsonEscape('a"b') = 'a\"b'.
  See Also: RenderLine. }
function JsonEscape(const Text: string): string;

{ Render one log line as JSON, without the newline.

  Description: fields in the order ts (UTC, milliseconds), level, service,
  msg, taskId (null), traceId and spanId (null when empty), detail (omitted
  when empty).

  Business Justification: the log format is a contract with Loki and the
  dashboards (P7.1).

  @param(Level severity, llDebug..llError)
  @param(Msg message, English)
  @param(TraceId trace id (32 lowercase hex) or an empty string)
  @param(SpanId caller's span id (16 lowercase hex) or an empty string)
  @param(Detail extra detail or an empty string)
  @returns(one JSON object)

  Errors: none. Side Effects: reads the clock. Complexity: O(n).
  Thread Safety: safe.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: RenderLine(llInfo, 'stopped', '', '', '').
  See Also: LogWrite. }
function RenderLine(Level: TLogLevel; const Msg, TraceId, SpanId, Detail: string): string;

{ Write one JSON log line to stdout.

  Description: drops lines below the threshold; flushes every line.

  Business Justification: logs are collected by Loki from stdout (P7.1) and
  correlated by trace.

  @param(Level severity)
  @param(Msg message, English)
  @param(TraceId trace id or an empty string)
  @param(SpanId caller's span id or an empty string)
  @param(Detail extra detail or an empty string)

  Errors: none. Side Effects: writes to stdout. Complexity: O(n).
  Thread Safety: safe; lines of concurrent requests never interleave.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: LogWrite(llInfo, 'listening', '', '', 'port 8080').
  See Also: RenderLine. }
procedure LogWrite(
    Level: TLogLevel;
    const Msg: string;
    const TraceId: string = '';
    const SpanId: string = '';
    const Detail: string = ''
);

implementation

uses
  SysUtils,
  DateUtils,
  SyncObjs;

const
  { Names of the levels llDebug..llError as written in the level field. }
  LevelNames: array[llDebug..llError] of string = ('debug', 'info', 'warn', 'error');
var
  { Serialises configuration and writes, so that lines never interleave. }
  LogLock: TCriticalSection;
  { Service name written in every line (set by LogInit). }
  LogService: string = 'digit';
  { Minimum level written (set by LogInit). }
  LogThreshold: TLogLevel = llInfo;

procedure LogInit(const Service: string; Threshold: TLogLevel);
begin
  LogLock.Acquire;
  try
    LogService := Service;
    LogThreshold := Threshold;
  finally
    LogLock.Release;
  end;
end;

function ParseLevel(const Name: string; Fallback: TLogLevel): TLogLevel;
var
  Level: TLogLevel;
begin
  Result := Fallback;
  for Level := llDebug to llError do
    if Name = LevelNames[Level] then
      Result := Level;
end;

function JsonEscape(const Text: string): string;
var
  C: char;
begin
  Result := '';
  for C in Text do
    case C of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #10: Result := Result + '\n';
      #13: Result := Result + '\r';
      #9: Result := Result + '\t';
      #0..#8, #11, #12, #14..#31: Result := Result + '\u' + LowerCase(IntToHex(Ord(C), 4));
    else
      Result := Result + C;
    end;
end;

function RenderLine(Level: TLogLevel; const Msg, TraceId, SpanId, Detail: string): string;
var
  Service: string;
  Name: string;
begin
  LogLock.Acquire;
  try
    Service := LogService;
  finally
    LogLock.Release;
  end;
  if Level = llOff then
    Name := LevelNames[llError]
  else
    Name := LevelNames[Level];
  Result :=
      '{"ts":"'
          + FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz"Z"', LocalTimeToUniversal(Now))
          + '","level":"'
          + Name
          + '","service":"'
          + JsonEscape(Service)
          + '","msg":"'
          + JsonEscape(Msg)
          + '","taskId":null';
  if TraceId = '' then
    Result := Result + ',"traceId":null'
  else
    Result := Result + ',"traceId":"' + JsonEscape(TraceId) + '"';
  if SpanId = '' then
    Result := Result + ',"spanId":null'
  else
    Result := Result + ',"spanId":"' + JsonEscape(SpanId) + '"';
  if Detail <> '' then
    Result := Result + ',"detail":"' + JsonEscape(Detail) + '"';
  Result := Result + '}';
end;

procedure LogWrite(
    Level: TLogLevel;
    const Msg: string;
    const TraceId: string;
    const SpanId: string;
    const Detail: string
);
var
  Line: string;
  Threshold: TLogLevel;
begin
  LogLock.Acquire;
  try
    Threshold := LogThreshold;
  finally
    LogLock.Release;
  end;
  if (Level < Threshold) or (Level = llOff) then
    Exit;
  Line := RenderLine(Level, Msg, TraceId, SpanId, Detail);
  LogLock.Acquire;
  try
    WriteLn(Line);
    Flush(Output);
  finally
    LogLock.Release;
  end;
end;

initialization
  LogLock := TCriticalSection.Create;

finalization
  LogLock.Free;

end.
