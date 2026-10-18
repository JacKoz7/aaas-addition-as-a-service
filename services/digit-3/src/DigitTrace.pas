// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          src/DigitTrace.pas
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Parsing of the W3C traceparent header, so that log lines
//                  carry the caller's trace and span ids.
// Related Docs:    CLAUDE.md 6.1, contracts/http/digit.yaml

{ W3C Trace Context (traceparent) parsing.

  Until the instrumentation of P7.2 the service creates no spans; it
  continues the caller's trace in its logs.

  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
unit DigitTrace;

{$MODE objfpc}
{$H+}

interface

type
  { Trace and parent span ids of a traceparent header.
    Thread Safety: plain value. }
  TTraceContext = record
    { 32 lowercase hex digits. }
    TraceId: string;
    { 16 lowercase hex digits of the caller's span. }
    SpanId: string;
  end;

{ Parse a traceparent header value.

  Description: accepts version-traceid-parentid-flags with 2, 32, 16 and 2
  lowercase hex digits, a version other than ff, and ids that are not all
  zeros (W3C Trace Context, level 1). Anything else, including an empty
  header, is rejected and Context is left untouched.

  Business Justification: logs of a digit call join the trace of the
  addition (CLAUDE.md 6.1).

  @param(Header header value, empty when absent)
  @param(Context receives the ids when the header is valid)
  @returns(True when the header is valid)

  Errors: none (False for invalid input). Side Effects: none.
  Complexity: O(1). Thread Safety: safe.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: ParseTraceparent('00-4bf9...4736-00f0...02b7-01', Ctx) = True.
  See Also: IsHex, LogWrite. }
function ParseTraceparent(const Header: string; var Context: TTraceContext): boolean;

{ Whether a part is lowercase hex and, when NonZero, not all zeros.

  Description: used for each dash-separated part of the header.

  Business Justification: W3C Trace Context forbids upper case and all-zero
  ids.

  @param(Part one part of the header)
  @param(NonZero also require a non-zero digit)
  @returns(True when the part is valid)

  Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: IsHex('00f067aa0ba902b7', True) = True.
  See Also: ParseTraceparent. }
function IsHex(const Part: string; NonZero: boolean): boolean;

implementation

function IsHex(const Part: string; NonZero: boolean): boolean;
var
  C: char;
  AnyNonZero: boolean;
begin
  AnyNonZero := False;
  for C in Part do begin
    if not (C in ['0'..'9', 'a'..'f']) then
      Exit(False);
    AnyNonZero := AnyNonZero or (C <> '0');
  end;
  Result := AnyNonZero or not NonZero;
end;

function ParseTraceparent(const Header: string; var Context: TTraceContext): boolean;
begin
  Result :=
      (Length(Header) = 55)
          and (Header[3] = '-')
          and (Header[36] = '-')
          and (Header[53] = '-')
          and IsHex(Copy(Header, 1, 2), False)
          and (Copy(Header, 1, 2) <> 'ff')
          and IsHex(Copy(Header, 4, 32), True)
          and IsHex(Copy(Header, 37, 16), True)
          and IsHex(Copy(Header, 54, 2), False);
  if Result then begin
    Context.TraceId := Copy(Header, 4, 32);
    Context.SpanId := Copy(Header, 37, 16);
  end;
end;

end.
