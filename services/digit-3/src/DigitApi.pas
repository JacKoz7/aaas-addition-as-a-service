// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          src/DigitApi.pas
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The HTTP contract of the digit service as a function
//                  from (method, path) to a reply: routing, JSON bodies,
//                  problem details, health and metrics.
// Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

{ Request handling of contracts/http/digit.yaml, independent of the HTTP
  server.

  DigitService passes each request to TApi.Handle and sends the reply it
  returns; the unit tests call TApi.Handle directly.

  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
unit DigitApi;

{$MODE objfpc}
{$H+}

interface

uses
  SyncObjs,
  DigitStore,
  DigitMetrics;

type
  { An HTTP reply to send. Thread Safety: plain value. }
  TReply = record
    { HTTP status code. }
    Status: integer;
    { Value of Content-Type. }
    ContentType: string;
    { Value of Allow; empty when not sent (405 only). }
    Allow: string;
    { Response body. }
    Body: string;
  end;

  { The digit contract over one database.

    Description: holds references to the store and the metrics, which must
    outlive it.

    Business Justification: the single implementation of the contract that
    every digit request goes through; the value is read on every request,
    never cached or hard-coded (CLAUDE.md 4.4).

    Thread Safety: safe; database access is serialised with a lock, so the
    threaded server may call Handle concurrently.
    Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
  TApi = class
  private
    { Database of the service. }
    FStore: TStore;
    { The configured digit (AAAS_DIGIT). }
    FDigit: integer;
    { Request counters. }
    FMetrics: TMetrics;
    { Serialises use of the single SQLite connection. }
    FLock: TCriticalSection;

    { Read the digit row and check that it names the configured digit.

      Description: a failure is logged at error level.

      Business Justification: a service must never answer for another
      digit, for example after its volume was mixed up with another one.

      @param(Row receives the row on success)
      @returns(True when the row was read and matches the digit)

      Errors: False on failure. Side Effects: one SELECT under the lock;
      logs failures. Complexity: O(1). Thread Safety: safe. Owner: AEC.
      Since: digit-3 0.1.0. Example: if ReadRow(Row) then ...
      See Also: TStore.Read. }
    function ReadRow(out Row: TDigitRow): boolean;

    { Answer GET /value or GET /next.

      Description: reads the row on every call; 503 problem details when it
      cannot be read. Counts the request in the metrics.

      Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).

      @param(Endpoint which of the two operations)
      @returns(the reply)

      Errors: none (503 reply on failure). Side Effects: one SELECT; one
      counter increment. Complexity: O(1). Thread Safety: safe. Owner: AEC.
      Since: digit-3 0.1.0. Example: Reply := AnswerDigit(epNext).
      See Also: Handle. }
    function AnswerDigit(Endpoint: TEndpoint): TReply;
  public

    { Bind the contract to a database and counters; nothing is read until
      the first request.

      @param(Store open, migrated database of the service)
      @param(Digit the digit the service represents, 0..9)
      @param(Metrics counters updated by /value and /next)

      Errors: none. Side Effects: creates the lock. Complexity: O(1).
      Thread Safety: not applicable. Owner: AEC. Since: digit-3 0.1.0.
      Example: Api := TApi.Create(Store, 3, Metrics). See Also: Handle. }
    constructor Create(Store: TStore; Digit: integer; Metrics: TMetrics);

    { Free the lock (the store and the metrics are not owned).

      Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
      not safe while requests run. Owner: AEC. Since: digit-3 0.1.0.
      Example: Api.Free. See Also: Create. }
    destructor Destroy; override;

    { Answer one request according to contracts/http/digit.yaml.

      Description: GET /value answers 200 with digit and value; GET /next
      200 with digit, next and carry, both from the database; GET /health
      200 with status ok and checks.database ok when the row can be read
      and names the configured digit, otherwise 503 with error; GET /metrics
      200 Prometheus text; another method on one of these paths 405 problem
      details with Allow: GET; any other path 404 problem details. When the
      row cannot be read or names another digit, /value and /next answer
      503 problem details and count an error.

      Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).

      @param(Method HTTP method, upper case)
      @param(Path request path without the query string)
      @returns(the reply)

      Errors: none (404, 405 or 503 replies). Side Effects: reads the
      database; updates the metrics; logs database failures.
      Complexity: O(1). Thread Safety: safe. Owner: AEC.
      Since: digit-3 0.1.0. Example: Reply := Api.Handle('GET', '/next').
      See Also: Problem. }
    function Handle(const Method, Path: string): TReply;
  end;

{ Build a problem details reply (RFC 9457).

  Description: type is about:blank; title and detail are JSON-escaped.

  Business Justification: every AaaS error is problem details
  (CLAUDE.md 4.1).

  @param(Status HTTP status)
  @param(Title short summary of the problem type)
  @param(Detail explanation of this occurrence)
  @returns(the reply with Content-Type application/problem+json)

  Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: Reply := Problem(404, 'Not Found', 'no such path').
  See Also: TApi.Handle. }
function Problem(Status: integer; const Title, Detail: string): TReply;

implementation

uses
  SysUtils,
  DigitLog;

const
  { Media type of JSON bodies. }
  JsonType = 'application/json';
  { Media type of problem details (RFC 9457). }
  ProblemType = 'application/problem+json';
  { Media type of the Prometheus text exposition. }
  PrometheusType = 'text/plain; version=0.0.4';

function Problem(Status: integer; const Title, Detail: string): TReply;
begin
  Result.Status := Status;
  Result.ContentType := ProblemType;
  Result.Allow := '';
  Result.Body :=
      '{"type":"about:blank","title":"'
          + JsonEscape(Title)
          + '","status":'
          + IntToStr(Status)
          + ',"detail":"'
          + JsonEscape(Detail)
          + '"}';
end;

constructor TApi.Create(Store: TStore; Digit: integer; Metrics: TMetrics);
begin
  inherited Create;
  FStore := Store;
  FDigit := Digit;
  FMetrics := Metrics;
  FLock := TCriticalSection.Create;
end;

destructor TApi.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

function TApi.ReadRow(out Row: TDigitRow): boolean;
begin
  FLock.Acquire;
  try
    try
      Row := FStore.read;
    except
      on E: EStoreError do begin
        LogWrite(llError, 'cannot read the digit from the database', '', '', E.Message);
        Exit(False);
      end;
    end;
  finally
    FLock.Release;
  end;
  Result := Row.Digit = FDigit;
  if not Result then
    LogWrite(llError, 'the database holds another digit');
end;

function TApi.AnswerDigit(Endpoint: TEndpoint): TReply;
var
  Row: TDigitRow;
begin
  if not ReadRow(Row) then begin
    FMetrics.Count(Endpoint, ocError);
    Exit(Problem(503, 'Service Unavailable', 'the digit cannot be read from the database; retry the call'));
  end;
  FMetrics.Count(Endpoint, ocOk);
  Result.Status := 200;
  Result.ContentType := JsonType;
  Result.Allow := '';
  if Endpoint = epValue then
    Result.Body := Format('{"digit":%d,"value":%d}', [Row.Digit, Row.Value])
  else
    Result.Body :=
        Format('{"digit":%d,"next":%d,"carry":%s}', [Row.Digit, Row.Next, BoolToStr(Row.Carry, 'true', 'false')]);
end;

function TApi.Handle(const Method, Path: string): TReply;
var
  Row: TDigitRow;
  Ok: boolean;
begin
  if (Path <> '/value') and (Path <> '/next') and (Path <> '/health') and (Path <> '/metrics') then
    Exit(Problem(404, 'Not Found', 'the digit service has no such path'));
  if Method <> 'GET' then begin
    Result := Problem(405, 'Method Not Allowed', 'only GET is allowed on this path');
    Result.Allow := 'GET';
    Exit;
  end;
  if Path = '/value' then
    Exit(AnswerDigit(epValue));
  if Path = '/next' then
    Exit(AnswerDigit(epNext));
  Result.Allow := '';
  if Path = '/health' then begin
    Ok := ReadRow(Row);
    Result.ContentType := JsonType;
    if Ok then begin
      Result.Status := 200;
      Result.Body := '{"status":"ok","checks":{"database":"ok"}}';
    end
    else begin
      Result.Status := 503;
      Result.Body := '{"status":"error","checks":{"database":"error"}}';
    end;
    Exit;
  end;
  Result.Status := 200;
  Result.ContentType := PrometheusType;
  Result.Body := FMetrics.Render;
end;

end.
