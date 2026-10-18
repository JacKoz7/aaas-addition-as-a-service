! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/trace.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         Parsing of the W3C `traceparent` header, so that log
!                  lines carry the caller's trace and span ids.
! Related Docs:    CLAUDE.md 6.1, contracts/http/digit.yaml

!> W3C Trace Context (`traceparent`) parsing.
!>
!> **Description:** Until the instrumentation of P7.2 the service creates
!> no spans; it continues the caller's trace in its logs.
!>
!> **Business Justification:** Logs of a digit call join the trace of the
!> addition (CLAUDE.md 6.1).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_log]]
module digit_trace
  implicit none
  private

  public :: trace_context, parse_traceparent

  !> Trace and parent span ids of a `traceparent` header.
  type :: trace_context
    !> 32 lowercase hex digits.
    character(len=32) :: trace_id = ''
    !> 16 lowercase hex digits of the caller's span.
    character(len=16) :: span_id = ''
  end type trace_context

contains

  !> Parse a `traceparent` header value.
  !>
  !> **Description:** Accepts `<version>-<trace-id>-<parent-id>-<flags>`
  !> with 2, 32, 16 and 2 lowercase hex digits, a version other than `ff`,
  !> and ids that are not all zeros (W3C Trace Context, level 1). Anything
  !> else, including an empty header, is rejected and `context` is left
  !> untouched.
  !>
  !> **Business Justification:** Logs of a digit call join the trace of the
  !> addition (CLAUDE.md 6.1).
  !>
  !> **Returns:** True when the header is valid. **Errors:** None (false
  !> for invalid input). **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `ok = parse_traceparent('00-4bf9...4736-00f0...02b7-01', ctx)`
  !>
  !> **See Also:** [[log_write]]
  function parse_traceparent(header, context) result(valid)
    !> Header value.
    character(len=*), intent(in) :: header
    !> Receives the ids when the header is valid.
    type(trace_context), intent(inout) :: context
    !> True when the header is valid.
    logical :: valid
    valid = .false.
    if (len(header) /= 55) return
    if (header(3:3) /= '-' .or. header(36:36) /= '-' .or. header(53:53) /= '-') return
    if (.not. is_hex(header(1:2), .false.) .or. header(1:2) == 'ff') return
    if (.not. is_hex(header(4:35), .true.) .or. .not. is_hex(header(37:52), .true.)) return
    if (.not. is_hex(header(54:55), .false.)) return
    context%trace_id = header(4:35)
    context%span_id = header(37:52)
    valid = .true.
  end function parse_traceparent

  !> Whether a part is lowercase hex and, when `nonzero`, not all zeros.
  !>
  !> **Description:** Used for each dash-separated part of the header.
  !>
  !> **Business Justification:** W3C Trace Context forbids upper case and
  !> all-zero ids.
  !>
  !> **Returns:** True when the part is valid. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `is_hex('00f067aa0ba902b7', .true.)` is true.
  !>
  !> **See Also:** [[parse_traceparent]]
  pure function is_hex(part, nonzero) result(valid)
    !> One part of the header.
    character(len=*), intent(in) :: part
    !> Also require a non-zero digit.
    logical, intent(in) :: nonzero
    !> True when the part is valid.
    logical :: valid
    integer :: i !! Loop index.
    valid = .true.
    do i = 1, len(part)
      if (.not. ((part(i:i) >= '0' .and. part(i:i) <= '9') .or. (part(i:i) >= 'a' .and. part(i:i) <= 'f'))) then
        valid = .false.
        return
      end if
    end do
    if (nonzero) valid = verify(part, '0') /= 0
  end function is_hex

end module digit_trace
