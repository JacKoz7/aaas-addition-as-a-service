// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          tests/testrunner.lpr
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Runs every registered fpcunit test and exits non-zero
//                  when a test fails or raises.
// Related Docs:    tests/TestDigit.pas, services/digit-3/Dockerfile

{ Test runner of digit-3: runs the fpcunit registry, prints every failure
  and error and a summary, and sets the exit code to 1 when one occurred.
  Logs are suppressed (threshold llOff), because the failure tests provoke
  error lines on purpose.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
program testrunner;

{$mode objfpc}{$H+}

uses
cthreads, SysUtils, fpcunit, testregistry, DigitLog, TestDigit;

var
  { Collected results of the run. }
  Results: TTestResult;
  { Index into the failure and error lists. }
  I: integer;

begin
  LogInit('digit-3-test', llOff);
  Results := TTestResult.Create;
  try
    GetTestRegistry.Run(Results);
    for I := 0 to Results.Failures.Count - 1 do
      WriteLn('FAIL ', TTestFailure(Results.Failures[I]).AsString);
    for I := 0 to Results.Errors.Count - 1 do
      WriteLn('ERROR ', TTestFailure(Results.Errors[I]).AsString);
    WriteLn(Format('%d tests, %d failures, %d errors', [Results.RunTests, Results.NumberOfFailures,
            Results.NumberOfErrors]));
    if not Results.WasSuccessful then
      ExitCode := 1;
  finally
    Results.Free;
end;
end.
