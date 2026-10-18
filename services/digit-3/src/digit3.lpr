// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          src/digit3.lpr
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Entry point of the digit-3 service.
// Related Docs:    src/DigitService.pas, services/digit-3/README.md

{ Process entry point of digit-3: runs DigitService.RunService and exits
  with its status (0 after a graceful stop, 1 when start-up fails).
  cthreads comes first, as the threaded HTTP server requires.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
program digit3;

{$mode objfpc}{$H+}

uses
cthreads,
DigitService;

begin
  ExitCode := RunService;
end.
