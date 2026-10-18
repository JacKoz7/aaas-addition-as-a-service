// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          src/DigitMetrics.pas
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Prometheus metrics of the digit service: the request
//                  counter shared by all ten digit services and the build
//                  information.
// Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

{ Request counter digit_requests_total and its exposition.

  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
unit DigitMetrics;

{$MODE objfpc}
{$H+}

interface

type
  { Arithmetic endpoint, label endpoint of the counter: GET /value or
    GET /next. }
  TEndpoint = (epValue, epNext);

  { Outcome of a request, label outcome of the counter: answered 200 (ok)
    or 503 (error, database unavailable). }
  TOutcome = (ocOk, ocError);

  { Counters of one service process; every sample exists from the start
    (value 0).

    Business Justification: one dashboard shows the traffic of all ten
    digit services (P7.3).

    Thread Safety: safe; counters are changed with interlocked operations.
    Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
  TMetrics = class
  private
    { Value of the digit label, 0..9. }
    FDigit: integer;
    { Service version for digit_build_info. }
    FVersion: string;
    { digit_requests_total samples by endpoint and outcome. }
    FRequests: array[TEndpoint, TOutcome] of int64;
  public

    { Create zeroed counters.

      @param(Digit the service's digit, 0..9)
      @param(Version service version)

      Errors: none. Side Effects: none. Complexity: O(1).
      Thread Safety: not applicable. Owner: AEC. Since: digit-3 0.1.0.
      Example: Metrics := TMetrics.Create(3, '0.1.0'). See Also: Count. }
    constructor Create(Digit: integer; const Version: string);

    { Count one answered request.

      Business Justification: traffic and errors per digit.

      @param(Endpoint endpoint answered)
      @param(Outcome outcome of the request)

      Errors: none. Side Effects: increments one counter. Complexity: O(1).
      Thread Safety: safe (interlocked). Owner: AEC. Since: digit-3 0.1.0.
      Example: Metrics.Count(epNext, ocOk). See Also: Render. }
    procedure Count(Endpoint: TEndpoint; Outcome: TOutcome);

    { Current value of one sample (used by the unit tests).

      @param(Endpoint endpoint)
      @param(Outcome outcome)
      @returns(number of counted requests)

      Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
      safe. Owner: AEC. Since: digit-3 0.1.0.
      Example: Metrics.Get(epNext, ocError). See Also: Count. }
    function Get(Endpoint: TEndpoint; Outcome: TOutcome): int64;

    { Render the Prometheus text exposition (format 0.0.4).

      Description: digit_requests_total with labels digit, endpoint and
      outcome (all four samples) and digit_build_info with labels digit and
      version, value 1.

      Business Justification: GET /metrics of the contract.

      @returns(the exposition text)

      Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
      safe (samples may be from slightly different instants). Owner: AEC.
      Since: digit-3 0.1.0. Example: Text := Metrics.Render.
      See Also: Count. }
    function Render: string;
  end;

implementation

uses
  SysUtils;

const
  { Values of the endpoint label. }
  EndpointNames: array[TEndpoint] of string = ('value', 'next');
  { Values of the outcome label. }
  OutcomeNames: array[TOutcome] of string = ('ok', 'error');

constructor TMetrics.Create(Digit: integer; const Version: string);
begin
  inherited Create;
  FDigit := Digit;
  FVersion := Version;
end;

procedure TMetrics.Count(Endpoint: TEndpoint; Outcome: TOutcome);
begin
  InterLockedIncrement64(FRequests[Endpoint, Outcome]);
end;

function TMetrics.Get(Endpoint: TEndpoint; Outcome: TOutcome): int64;
begin
  Result := InterlockedExchangeAdd64(FRequests[Endpoint, Outcome], 0);
end;

function TMetrics.Render: string;
var
  Endpoint: TEndpoint;
  Outcome: TOutcome;
begin
  Result :=
      '# HELP digit_requests_total Requests answered by the digit service.'#10
          + '# TYPE digit_requests_total counter'#10;
  for Endpoint := Low(TEndpoint) to High(TEndpoint) do
    for Outcome := Low(TOutcome) to High(TOutcome) do
      Result :=
          Result
              + Format(
                  'digit_requests_total{digit="%d",endpoint="%s",outcome="%s"} %d'#10,
                  [FDigit, EndpointNames[Endpoint], OutcomeNames[Outcome], Get(Endpoint, Outcome)]);
  Result :=
      Result
          + '# HELP digit_build_info Build information of the digit service.'#10
          + '# TYPE digit_build_info gauge'#10
          + Format('digit_build_info{digit="%d",version="%s"} 1'#10, [FDigit, FVersion]);
end;

end.
