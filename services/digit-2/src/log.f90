! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/log.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         Structured JSON logging on stdout with the fields of
!                  CLAUDE.md 6.1, JSON string escaping and UTC timestamps.
! Related Docs:    CLAUDE.md 6.1, services/digit-2/README.md, ADR-0022

!> Structured JSON logs (one object per line on stdout).
!>
!> **Description:** Every line has `ts`, `level`, `service`, `msg`,
!> `taskId`, `traceId` and `spanId` (CLAUDE.md 6.1), plus `detail` when
!> given. A digit call carries no task, so `taskId` is always null;
!> `traceId` and `spanId` come from the caller's `traceparent`.
!>
!> **Business Justification:** Logs are collected by Loki from stdout (P7.1)
!> and correlated by trace.
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_trace]]
module digit_log
  use, intrinsic :: iso_c_binding, only: c_long
  use, intrinsic :: iso_fortran_env, only: output_unit, int64
  use digit_posix, only: timespec, c_clock_gettime, clock_realtime
  implicit none
  private

  public :: level_debug, level_info, level_warn, level_error, level_off
  public :: log_init, parse_level, log_write, render_line, json_escape, format_timestamp

  !> Debug level: per-request details; off by default.
  integer, parameter :: level_debug = 0
  !> Info level: lifecycle events (start, migrations, shutdown).
  integer, parameter :: level_info = 1
  !> Warn level: recoverable problems.
  integer, parameter :: level_warn = 2
  !> Error level: failures.
  integer, parameter :: level_error = 3
  !> Threshold only: writes nothing (used by the unit tests).
  integer, parameter :: level_off = 4
  !> Names of the levels debug..error, padded to 5 characters.
  character(len=5), parameter :: level_names(0:3) = ['debug', 'info ', 'warn ', 'error']

  !> Service name written in every line (set by [[log_init]]).
  character(len=:), allocatable :: log_service
  !> Minimum level written (set by [[log_init]]).
  integer :: log_threshold = level_info

contains

  !> Configure the service name and the minimum level written.
  !>
  !> **Description:** Lines below `threshold` are dropped. Until called, the
  !> service name is `digit` and the threshold is info.
  !>
  !> **Business Justification:** Every line names its service; the level is
  !> configurable per environment.
  !>
  !> **Errors:** None. **Side Effects:** Sets module state.
  !>
  !> **Complexity:** O(n). **Thread Safety:** The service is single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call log_init('digit-2', level_info)`
  !>
  !> **See Also:** [[log_write]]
  subroutine log_init(service, threshold)
    !> Service name, for example `digit-2`.
    character(len=*), intent(in) :: service
    !> Minimum level written.
    integer, intent(in) :: threshold
    log_service = service
    log_threshold = threshold
  end subroutine log_init

  !> Parse a level name (`debug`, `info`, `warn`, `error`).
  !>
  !> **Description:** Case-sensitive; any other value, including an empty
  !> string (variable unset), yields `fallback`.
  !>
  !> **Business Justification:** The level comes from AAAS_LOG_LEVEL.
  !>
  !> **Returns:** The level. **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `level = parse_level('debug', level_info)`
  !>
  !> **See Also:** [[log_init]]
  pure function parse_level(name, fallback) result(level)
    !> Level name, or an empty string.
    character(len=*), intent(in) :: name
    !> Level returned for unknown names.
    integer, intent(in) :: fallback
    !> The parsed level.
    integer :: level
    integer :: i !! Loop index.
    level = fallback
    do i = level_debug, level_error
      if (name == trim(level_names(i))) level = i
    end do
  end function parse_level

  !> Escape a string for the inside of a JSON string literal.
  !>
  !> **Description:** Escapes the double quote and the backslash with a
  !> backslash, newline, carriage return and tab by their short escapes, and
  !> the other control characters as a `u00XX` escape.
  !>
  !> **Business Justification:** Log messages and problem details may
  !> contain arbitrary text.
  !>
  !> **Returns:** The escaped text. **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `json_escape('a"b')` is `a\"b`.
  !>
  !> **See Also:** [[render_line]]
  pure function json_escape(text) result(escaped)
    !> Text to escape.
    character(len=*), intent(in) :: text
    !> The escaped text.
    character(len=:), allocatable :: escaped
    character(len=6) :: unicode !! One `u00XX` escape.
    integer :: i !! Loop index.
    integer :: code !! Character code.
    escaped = ''
    do i = 1, len(text)
      code = iachar(text(i:i))
      select case (code)
      case (34)
        escaped = escaped//'\"'
      case (92)
        escaped = escaped//'\\'
      case (10)
        escaped = escaped//'\n'
      case (13)
        escaped = escaped//'\r'
      case (9)
        escaped = escaped//'\t'
      case (0:8, 11:12, 14:31)
        write (unicode, '(a,z4.4)') '\u', code
        escaped = escaped//to_lower(unicode)
      case default
        escaped = escaped//text(i:i)
      end select
    end do
  end function json_escape

  !> Lower-case the ASCII letters of a string.
  !>
  !> **Description:** Used for the hex digits of `u00XX` escapes.
  !>
  !> **Business Justification:** Matches the escapes of the reference
  !> implementation (`digit-0`).
  !>
  !> **Returns:** The text in lower case. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `to_lower('\u001B')` is `\u001b`.
  !>
  !> **See Also:** [[json_escape]]
  pure function to_lower(text) result(lower)
    !> Text.
    character(len=*), intent(in) :: text
    !> The text with A..Z replaced by a..z.
    character(len=len(text)) :: lower
    integer :: i !! Loop index.
    lower = text
    do i = 1, len(text)
      if (lower(i:i) >= 'A' .and. lower(i:i) <= 'Z') lower(i:i) = achar(iachar(lower(i:i)) + 32)
    end do
  end function to_lower

  !> Format a UTC time as ISO 8601 with milliseconds.
  !>
  !> **Description:** Converts days since the epoch to a civil date with the
  !> algorithm of Howard Hinnant (`civil_from_days`), valid for every date
  !> after 1970.
  !>
  !> **Business Justification:** The `ts` field of every log line
  !> (CLAUDE.md 6.1).
  !>
  !> **Returns:** `YYYY-MM-DDTHH:MM:SS.mmmZ`. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `format_timestamp(0_int64, 0)` is `1970-01-01T00:00:00.000Z`.
  !>
  !> **See Also:** [[render_line]]
  pure function format_timestamp(seconds, millis) result(text)
    !> Seconds since 1970-01-01T00:00:00Z, non-negative.
    integer(int64), intent(in) :: seconds
    !> Milliseconds, 0..999.
    integer, intent(in) :: millis
    !> The formatted time.
    character(len=24) :: text
    integer(int64) :: days !! Days since the epoch.
    integer(int64) :: secs !! Seconds of the day.
    integer(int64) :: z !! Days since 0000-03-01.
    integer(int64) :: era !! 400-year era.
    integer(int64) :: doe !! Day of the era.
    integer(int64) :: yoe !! Year of the era.
    integer(int64) :: doy !! Day of the year (from March).
    integer(int64) :: mp !! Month from March, 0..11.
    integer(int64) :: d !! Day of the month.
    integer(int64) :: m !! Month.
    integer(int64) :: y !! Year.
    days = seconds/86400_int64
    secs = modulo(seconds, 86400_int64)
    z = days + 719468_int64
    era = z/146097_int64
    doe = z - era*146097_int64
    yoe = (doe - doe/1460_int64 + doe/36524_int64 - doe/146096_int64)/365_int64
    y = yoe + era*400_int64
    doy = doe - (365_int64*yoe + yoe/4_int64 - yoe/100_int64)
    mp = (5_int64*doy + 2_int64)/153_int64
    d = doy - (153_int64*mp + 2_int64)/5_int64 + 1_int64
    if (mp < 10_int64) then
      m = mp + 3_int64
    else
      m = mp - 9_int64
    end if
    if (m <= 2_int64) y = y + 1_int64
    write (text, '(i4.4,"-",i2.2,"-",i2.2,"T",i2.2,":",i2.2,":",i2.2,".",i3.3,"Z")') &
      y, m, d, secs/3600_int64, modulo(secs/60_int64, 60_int64), modulo(secs, 60_int64), millis
  end function format_timestamp

  !> Render one log line as JSON, without the newline.
  !>
  !> **Description:** Fields in the order `ts`, `level`, `service`, `msg`,
  !> `taskId` (null), `traceId`, `spanId` (null when absent or empty),
  !> `detail` (omitted when absent).
  !>
  !> **Business Justification:** The log format is a contract with Loki and
  !> the dashboards (P7.1).
  !>
  !> **Returns:** One JSON object. **Errors:** None.
  !> **Side Effects:** Reads the clock.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `line = render_line(level_info, 'stopped')`
  !>
  !> **See Also:** [[log_write]]
  function render_line(level, msg, trace_id, span_id, detail) result(line)
    !> Severity, level_debug..level_error.
    integer, intent(in) :: level
    !> Message, English.
    character(len=*), intent(in) :: msg
    !> Trace id (32 lowercase hex), optional.
    character(len=*), intent(in), optional :: trace_id
    !> Caller's span id (16 lowercase hex), optional.
    character(len=*), intent(in), optional :: span_id
    !> Extra detail, optional.
    character(len=*), intent(in), optional :: detail
    !> The JSON object.
    character(len=:), allocatable :: line
    type(timespec) :: now !! Current wall-clock time.
    integer :: rc !! Return code of the C call.

    if (.not. allocated(log_service)) log_service = 'digit'
    rc = c_clock_gettime(clock_realtime, now)
    line = '{"ts":"'//format_timestamp(int(now%tv_sec, int64), int(now%tv_nsec/1000000_c_long)) &
           //'","level":"'//trim(level_names(min(max(level, level_debug), level_error))) &
           //'","service":"'//json_escape(log_service)//'","msg":"'//json_escape(msg)//'","taskId":null' &
           //optional_field('traceId', trace_id)//optional_field('spanId', span_id)
    if (present(detail)) line = line//',"detail":"'//json_escape(detail)//'"'
    line = line//'}'
  end function render_line

  !> Render `,"key":"value"` or `,"key":null` for an optional value.
  !>
  !> **Description:** An absent or empty value is null.
  !>
  !> **Business Justification:** `traceId` and `spanId` are always present,
  !> null without a trace (CLAUDE.md 6.1).
  !>
  !> **Returns:** The JSON fragment. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `optional_field('traceId')` is `,"traceId":null`.
  !>
  !> **See Also:** [[render_line]]
  pure function optional_field(key, value) result(fragment)
    !> Field name (plain ASCII).
    character(len=*), intent(in) :: key
    !> Field value, optional.
    character(len=*), intent(in), optional :: value
    !> The fragment.
    character(len=:), allocatable :: fragment
    fragment = ',"'//key//'":null'
    if (present(value)) then
      if (len(value) > 0) fragment = ',"'//key//'":"'//json_escape(value)//'"'
    end if
  end function optional_field

  !> Write one JSON log line to stdout.
  !>
  !> **Description:** Drops lines below the threshold; flushes every line.
  !>
  !> **Business Justification:** Structured logs of CLAUDE.md 6.1.
  !>
  !> **Errors:** None. **Side Effects:** Writes to stdout.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call log_write(level_info, 'listening', detail='port 8080')`
  !>
  !> **See Also:** [[render_line]]
  subroutine log_write(level, msg, trace_id, span_id, detail)
    !> Severity.
    integer, intent(in) :: level
    !> Message, English.
    character(len=*), intent(in) :: msg
    !> Trace id, optional.
    character(len=*), intent(in), optional :: trace_id
    !> Caller's span id, optional.
    character(len=*), intent(in), optional :: span_id
    !> Extra detail, optional.
    character(len=*), intent(in), optional :: detail
    if (level < log_threshold .or. level >= level_off) return
    write (output_unit, '(a)') render_line(level, msg, trace_id, span_id, detail)
    flush (output_unit)
  end subroutine log_write

end module digit_log
