// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          tests/TestDigit.pas
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Unit tests of digit-3 (fpcunit): migrations, the
//                  database read, every reply of the HTTP contract, the
//                  proof that answers come from the database, metrics,
//                  trace parsing and the log line format.
// Related Docs:    services/digit-3/README.md, contracts/http/digit.yaml

{ Unit tests of digit-3 (fpcunit).

  Each test opens a fresh in-memory database migrated with the real files
  of migrations/, so the tests exercise the same seed as the service. Run
  from the service directory (the build stage test does); the directory can
  be overridden with AAAS_MIGRATIONS_DIR.

  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
unit TestDigit;

{$MODE objfpc}
{$H+}

interface

uses
  fpcunit,
  testregistry,
  DigitStore,
  DigitMetrics,
  DigitApi;

type

  { Tests of the contract, the store and the counters over a migrated
    in-memory database for digit 3. Owner: AEC. Since: digit-3 0.1.0. }
  TDigitApiTest = class(TTestCase)
  private
    { In-memory database migrated with migrations/. }
    FStore: TStore;
    { Counters of the contract. }
    FMetrics: TMetrics;
    { The contract under test, digit 3. }
    FApi: TApi;
    { Files applied by the migration in SetUp. }
    FApplied: integer;
  protected
    { Create the database, the counters and the contract. }
    procedure SetUp; override;
    { Free the contract, the counters and the database. }
    procedure TearDown; override;
  published
    { Migrations create the seed once and are idempotent. }
    procedure TestMigrations;
    { GET /value and GET /next answer the contract's bodies. }
    procedure TestValueAndNext;
    { Answers follow the database, not the code (CLAUDE.md 4.4). }
    procedure TestAnswersComeFromTheDatabase;
    { An unreadable, foreign or duplicated row yields 503 and an unhealthy
      service. }
    procedure TestDatabaseFailures;
    { Unknown paths answer 404, other methods 405 with Allow: GET. }
    procedure TestErrors;
    { The counter counts value and next by outcome; the text is valid. }
    procedure TestMetrics;
  end;

  { Tests of traceparent parsing and of the log format.
    Owner: AEC. Since: digit-3 0.1.0. }
  THelpersTest = class(TTestCase)
  published
    { Valid traceparent headers are parsed, invalid ones rejected. }
    procedure TestTraceparent;
    { Log lines carry the fields of CLAUDE.md 6.1; escaping and levels. }
    procedure TestLogFormat;
  end;

{ Directory of the migration files used by the tests: AAAS_MIGRATIONS_DIR,
  or migrations relative to the working directory.
  @returns(the directory) }
function MigrationsDir: string;

implementation

uses
  SysUtils,
  DigitLog,
  DigitTrace;

function MigrationsDir: string;
begin
  Result := GetEnvironmentVariable('AAAS_MIGRATIONS_DIR');
  if Result = '' then
    Result := 'migrations';
end;

procedure TDigitApiTest.SetUp;
begin
  FStore := TStore.Create(':memory:');
  FApplied := FStore.Migrate(MigrationsDir);
  FMetrics := TMetrics.Create(3, 'test');
  FApi := TApi.Create(FStore, 3, FMetrics);
end;

procedure TDigitApiTest.TearDown;
begin
  FApi.Free;
  FMetrics.Free;
  FStore.Free;
end;

procedure TDigitApiTest.TestMigrations;
var
  Row: TDigitRow;
begin
  AssertEquals('first migration applies one file', 1, FApplied);
  AssertEquals('second migration applies nothing', 0, FStore.Migrate(MigrationsDir));
  Row := FStore.read;
  AssertEquals('digit', 3, Row.Digit);
  AssertEquals('value', 3, Row.Value);
  AssertEquals('next', 4, Row.Next);
  AssertFalse('carry', Row.Carry);
  try
    FStore.Migrate('/nonexistent-directory');
    Fail('a missing directory must raise');
  except
    on EStoreError do
      ;
  end;
end;

procedure TDigitApiTest.TestValueAndNext;
var
  Reply: TReply;
begin
  Reply := FApi.Handle('GET', '/value');
  AssertEquals(200, Reply.Status);
  AssertEquals('application/json', Reply.ContentType);
  AssertEquals('{"digit":3,"value":3}', Reply.Body);
  Reply := FApi.Handle('GET', '/next');
  AssertEquals(200, Reply.Status);
  AssertEquals('{"digit":3,"next":4,"carry":false}', Reply.Body);
  AssertEquals('no Allow on 200', '', Reply.Allow);
end;

procedure TDigitApiTest.TestAnswersComeFromTheDatabase;
begin
  FStore.Execute('UPDATE digit SET next = 7, carry = 1;');
  AssertEquals('{"digit":3,"next":7,"carry":true}', FApi.Handle('GET', '/next').Body);
end;

procedure TDigitApiTest.TestDatabaseFailures;
var
  Reply: TReply;
  Foreign: TApi;
begin
  Reply := FApi.Handle('GET', '/health');
  AssertEquals(200, Reply.Status);
  AssertEquals('{"status":"ok","checks":{"database":"ok"}}', Reply.Body);
  Foreign := TApi.Create(FStore, 4, FMetrics);
  try
    AssertEquals('foreign digit', 503, Foreign.Handle('GET', '/value').Status);
  finally
    Foreign.Free;
  end;
  FStore.Execute('INSERT INTO digit (digit, value, next, carry) VALUES (5, 5, 6, 0);');
  AssertEquals('two rows', 503, FApi.Handle('GET', '/value').Status);
  FStore.Execute('DELETE FROM digit;');
  Reply := FApi.Handle('GET', '/next');
  AssertEquals('empty table', 503, Reply.Status);
  AssertEquals('application/problem+json', Reply.ContentType);
  AssertTrue('503 body', Pos('"status":503', Reply.Body) > 0);
  Reply := FApi.Handle('GET', '/health');
  AssertEquals(503, Reply.Status);
  AssertEquals('{"status":"error","checks":{"database":"error"}}', Reply.Body);
  AssertEquals('next errors', 1, FMetrics.Get(epNext, ocError));
  AssertEquals('value errors', 2, FMetrics.Get(epValue, ocError));
end;

procedure TDigitApiTest.TestErrors;
var
  Reply: TReply;
begin
  Reply := FApi.Handle('GET', '/nope');
  AssertEquals(404, Reply.Status);
  AssertEquals('application/problem+json', Reply.ContentType);
  AssertEquals(
      '{"type":"about:blank","title":"Not Found","status":404,' + '"detail":"the digit service has no such path"}',
      Reply.Body
  );
  Reply := FApi.Handle('POST', '/value');
  AssertEquals(405, Reply.Status);
  AssertEquals('GET', Reply.Allow);
  AssertEquals('unknown path wins over method', 404, FApi.Handle('DELETE', '/nope').Status);
end;

procedure TDigitApiTest.TestMetrics;
var
  Reply: TReply;
begin
  FApi.Handle('GET', '/next');
  FApi.Handle('GET', '/next');
  FApi.Handle('GET', '/value');
  Reply := FApi.Handle('GET', '/metrics');
  AssertEquals(200, Reply.Status);
  AssertTrue('content type', Pos('text/plain', Reply.ContentType) = 1);
  AssertTrue('counter type', Pos('# TYPE digit_requests_total counter'#10, Reply.Body) > 0);
  AssertTrue('next ok', Pos('digit_requests_total{digit="3",endpoint="next",outcome="ok"} 2'#10, Reply.Body) > 0);
  AssertTrue('value ok', Pos('digit_requests_total{digit="3",endpoint="value",outcome="ok"} 1'#10, Reply.Body) > 0);
  AssertTrue(
      'zero sample',
      Pos('digit_requests_total{digit="3",endpoint="value",outcome="error"} 0'#10, Reply.Body) > 0
  );
  AssertTrue('build info', Pos('digit_build_info{digit="3",version="test"} 1'#10, Reply.Body) > 0);
end;

procedure THelpersTest.TestTraceparent;
var
  Ctx: TTraceContext;
begin
  Ctx := Default(TTraceContext);
  AssertTrue(ParseTraceparent('00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01', Ctx));
  AssertEquals('4bf92f3577b34da6a3ce929d0e0e4736', Ctx.TraceId);
  AssertEquals('00f067aa0ba902b7', Ctx.SpanId);
  AssertFalse('empty', ParseTraceparent('', Ctx));
  AssertFalse('zero id', ParseTraceparent('00-00000000000000000000000000000000-00f067aa0ba902b7-01', Ctx));
  AssertFalse('upper case', ParseTraceparent('00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01', Ctx));
  AssertFalse('version ff', ParseTraceparent('ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01', Ctx));
  AssertFalse('too short', ParseTraceparent('00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7', Ctx));
end;

procedure THelpersTest.TestLogFormat;
var
  Line: string;
begin
  AssertEquals('a\"b\\c\nd\u0001', JsonEscape('a"b\c'#10'd'#1));
  LogInit('digit-3-test', llOff);
  Line := RenderLine(llWarn, 'a "quoted" message', '4bf92f3577b34da6a3ce929d0e0e4736', '00f067aa0ba902b7', 'detail');
  AssertTrue('ts first', Pos('{"ts":"', Line) = 1);
  AssertTrue(
      'fields',
      Pos(
              'Z","level":"warn","service":"digit-3-test","msg":"a \"quoted\" message","taskId":null,'
                  + '"traceId":"4bf92f3577b34da6a3ce929d0e0e4736","spanId":"00f067aa0ba902b7","detail":"detail"}',
              Line)
          > 0
  );
  Line := RenderLine(llInfo, 'x', '', '', '');
  AssertTrue('null trace, no detail', Pos('"traceId":null,"spanId":null}', Line) > 0);
  AssertTrue('debug', ParseLevel('debug', llInfo) = llDebug);
  AssertTrue('error', ParseLevel('error', llInfo) = llError);
  AssertTrue('unknown', ParseLevel('verbose', llWarn) = llWarn);
  AssertTrue('unset', ParseLevel('', llInfo) = llInfo);
end;

initialization
  RegisterTest(TDigitApiTest);
  RegisterTest(THelpersTest);

end.
