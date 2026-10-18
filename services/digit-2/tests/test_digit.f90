! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          tests/test_digit.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         Unit tests of digit-2: migrations, the database read,
!                  every reply of the HTTP contract, the proof that answers
!                  come from the database, metrics, request parsing, the
!                  response format, trace parsing and the log format.
! Related Docs:    services/digit-2/README.md, contracts/http/digit.yaml

!> Unit tests (no framework: a check subroutine and a runner).
!>
!> **Description:** Each test opens a fresh in-memory database migrated
!> with the real files of `migrations/`, so the tests exercise the same
!> seed as the service. Run from the service directory (the build stage
!> `test` does); the directory can be overridden with
!> AAAS_MIGRATIONS_DIR. Exits with status 1 when a check fails.
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
program test_digit
  use, intrinsic :: iso_c_binding, only: c_int
  use, intrinsic :: iso_fortran_env, only: int64, error_unit
  use digit_posix, only: c_exit
  use digit_log
  use digit_trace
  use digit_store
  use digit_metrics
  use digit_api
  use digit_http, only: parse_request, format_response
  implicit none

  !> Number of executed checks.
  integer :: checks = 0
  !> Number of failed checks.
  integer :: failures = 0

  call log_init('digit-2-test', level_off)
  call test_migrations()
  call test_value_and_next()
  call test_answers_come_from_the_database()
  call test_database_failures()
  call test_errors()
  call test_metrics()
  call test_request_parsing()
  call test_response_format()
  call test_trace()
  call test_log_format()
  print '(i0," checks, ",i0," failed")', checks, failures
  if (failures > 0) call c_exit(1_c_int)

contains

  !> Record one check; report a failure with its label.
  !>
  !> **Description:** Prints `FAIL <label>` to stderr when `condition` is
  !> false.
  !>
  !> **Errors:** None. **Side Effects:** Updates the counters.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Not applicable.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call check(reply%status == 200, 'value status')`
  subroutine check(condition, label)
    !> Expression that must be true.
    logical, intent(in) :: condition
    !> Name of the check.
    character(len=*), intent(in) :: label
    checks = checks + 1
    if (.not. condition) then
      failures = failures + 1
      write (error_unit, '(a)') 'FAIL '//label
    end if
  end subroutine check

  !> Directory of the migration files used by the tests.
  !>
  !> **Description:** AAAS_MIGRATIONS_DIR, or `migrations`.
  !>
  !> **Returns:** The directory. **Errors:** None.
  !> **Side Effects:** Reads the environment.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Not applicable.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call store_migrate(st, migrations_dir(), applied, ok, message)`
  function migrations_dir() result(dir)
    !> The directory.
    character(len=:), allocatable :: dir
    integer :: length !! Length of the value.
    integer :: status !! I/O or environment status code.
    call get_environment_variable('AAAS_MIGRATIONS_DIR', length=length, status=status)
    if (status /= 0 .or. length == 0) then
      dir = 'migrations'
    else
      allocate (character(len=length) :: dir)
      call get_environment_variable('AAAS_MIGRATIONS_DIR', dir)
    end if
  end function migrations_dir

  !> Open a migrated in-memory database and fresh counters for digit 2.
  !>
  !> **Description:** Stops the run when the database cannot be prepared,
  !> because every later check would be meaningless.
  !>
  !> **Errors:** Exits with status 2 on failure.
  !> **Side Effects:** Allocates an in-memory database.
  !>
  !> **Complexity:** O(s). **Thread Safety:** Not applicable.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call setup(st, m, applied)`
  subroutine setup(store, metrics, applied)
    !> Receives the database.
    type(store_t), intent(out) :: store
    !> Receives zeroed counters.
    type(metrics_t), intent(out) :: metrics
    !> Files applied.
    integer, intent(out) :: applied
    logical :: ok !! Outcome of the last step.
    character(len=:), allocatable :: message !! Reason of a failure.
    call store_open(store, ':memory:', ok, message)
    if (ok) call store_migrate(store, migrations_dir(), applied, ok, message)
    if (.not. ok) then
      write (error_unit, '(a)') 'cannot prepare the test database: '//message
      call c_exit(2_c_int)
    end if
    call metrics_init(metrics, 2, 'test')
  end subroutine setup

  !> Migrations create the seed once and are idempotent.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_migrations()
    type(store_t) :: store !! Migrated in-memory database.
    type(metrics_t) :: metrics !! Counters of the test.
    type(digit_row) :: row !! Row read back.
    integer :: applied !! Migrations applied.
    logical :: ok !! Outcome of the last step.
    character(len=:), allocatable :: message !! Reason of a failure.
    call setup(store, metrics, applied)
    call check(applied == 1, 'first migration applies one file')
    call store_migrate(store, migrations_dir(), applied, ok, message)
    call check(ok .and. applied == 0, 'second migration applies nothing')
    call store_read(store, row, ok, message)
    call check(ok .and. row%digit == 2 .and. row%value == 2 .and. row%next == 3 .and. .not. row%carry, 'seed row')
    call store_migrate(store, '/nonexistent-directory', applied, ok, message)
    call check(.not. ok, 'missing migrations directory fails')
    call store_close(store)
  end subroutine test_migrations

  !> GET /value and GET /next answer the contract's bodies.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_value_and_next()
    type(store_t) :: store !! Migrated in-memory database.
    type(metrics_t) :: metrics !! Counters of the test.
    type(reply_t) :: reply !! Reply under test.
    integer :: applied !! Migrations applied.
    call setup(store, metrics, applied)
    reply = api_handle(store, 2, metrics, 'GET', '/value')
    call check(reply%status == 200, 'value status')
    call check(reply%content_type == 'application/json', 'value content type')
    call check(reply%body == '{"digit":2,"value":2}', 'value body')
    reply = api_handle(store, 2, metrics, 'GET', '/next')
    call check(reply%status == 200, 'next status')
    call check(reply%body == '{"digit":2,"next":3,"carry":false}', 'next body')
    call check(len(reply%allow) == 0, 'no Allow on 200')
    call store_close(store)
  end subroutine test_value_and_next

  !> Answers follow the database, not the code (CLAUDE.md 4.4).
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_answers_come_from_the_database()
    type(store_t) :: store !! Migrated in-memory database.
    type(metrics_t) :: metrics !! Counters of the test.
    type(reply_t) :: reply !! Reply under test.
    integer :: applied !! Migrations applied.
    logical :: ok !! Outcome of the last step.
    character(len=:), allocatable :: message !! Reason of a failure.
    call setup(store, metrics, applied)
    call store_exec(store, 'UPDATE digit SET next = 7, carry = 1;', ok, message)
    call check(ok, 'update the row')
    reply = api_handle(store, 2, metrics, 'GET', '/next')
    call check(reply%body == '{"digit":2,"next":7,"carry":true}', 'next follows the row')
    call store_close(store)
  end subroutine test_answers_come_from_the_database

  !> An unreadable, foreign or duplicated row yields 503 and an unhealthy
  !> service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_database_failures()
    type(store_t) :: store !! Migrated in-memory database.
    type(metrics_t) :: metrics !! Counters of the test.
    type(reply_t) :: reply !! Reply under test.
    integer :: applied !! Migrations applied.
    logical :: ok !! Outcome of the last step.
    character(len=:), allocatable :: message !! Reason of a failure.
    call setup(store, metrics, applied)
    reply = api_handle(store, 2, metrics, 'GET', '/health')
    call check(reply%status == 200, 'health ok')
    call check(reply%body == '{"status":"ok","checks":{"database":"ok"}}', 'health body ok')
    reply = api_handle(store, 4, metrics, 'GET', '/value')
    call check(reply%status == 503, 'foreign digit answers 503')
    call store_exec(store, 'INSERT INTO digit (digit, value, next, carry) VALUES (5, 5, 6, 0);', ok, message)
    reply = api_handle(store, 2, metrics, 'GET', '/value')
    call check(reply%status == 503, 'two rows answer 503')
    call store_exec(store, 'DELETE FROM digit;', ok, message)
    reply = api_handle(store, 2, metrics, 'GET', '/next')
    call check(reply%status == 503, 'empty table answers 503')
    call check(reply%content_type == 'application/problem+json', '503 is problem+json')
    call check(index(reply%body, '"status":503') > 0, '503 body')
    reply = api_handle(store, 2, metrics, 'GET', '/health')
    call check(reply%status == 503, 'health 503')
    call check(reply%body == '{"status":"error","checks":{"database":"error"}}', 'health body error')
    call check(metrics%requests(endpoint_next, outcome_error) == 1_int64, 'next error counted')
    call check(metrics%requests(endpoint_value, outcome_error) == 2_int64, 'value errors counted')
    call store_close(store)
  end subroutine test_database_failures

  !> Unknown paths answer 404, other methods 405 with Allow: GET.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_errors()
    type(store_t) :: store !! Migrated in-memory database.
    type(metrics_t) :: metrics !! Counters of the test.
    type(reply_t) :: reply !! Reply under test.
    integer :: applied !! Migrations applied.
    call setup(store, metrics, applied)
    reply = api_handle(store, 2, metrics, 'GET', '/nope')
    call check(reply%status == 404, '404 status')
    call check(reply%content_type == 'application/problem+json', '404 content type')
    call check(reply%body == '{"type":"about:blank","title":"Not Found","status":404,'// &
               '"detail":"the digit service has no such path"}', '404 body')
    reply = api_handle(store, 2, metrics, 'POST', '/value')
    call check(reply%status == 405 .and. reply%allow == 'GET', '405 with Allow')
    reply = api_handle(store, 2, metrics, 'DELETE', '/nope')
    call check(reply%status == 404, 'unknown path wins over method')
    call store_close(store)
  end subroutine test_errors

  !> The counter counts value and next by outcome; the text is valid.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_metrics()
    type(store_t) :: store !! Migrated in-memory database.
    type(metrics_t) :: metrics !! Counters of the test.
    type(reply_t) :: reply !! Reply under test.
    integer :: applied !! Migrations applied.
    !> Line feed ending every exposition line.
    character(len=1), parameter :: lf = new_line('a')
    call setup(store, metrics, applied)
    reply = api_handle(store, 2, metrics, 'GET', '/next')
    reply = api_handle(store, 2, metrics, 'GET', '/next')
    reply = api_handle(store, 2, metrics, 'GET', '/value')
    reply = api_handle(store, 2, metrics, 'GET', '/metrics')
    call check(reply%status == 200, 'metrics status')
    call check(reply%content_type(1:10) == 'text/plain', 'metrics content type')
    call check(index(reply%body, '# TYPE digit_requests_total counter'//lf) > 0, 'counter type')
    call check(index(reply%body, 'digit_requests_total{digit="2",endpoint="next",outcome="ok"} 2'//lf) > 0, &
               'next ok sample')
    call check(index(reply%body, 'digit_requests_total{digit="2",endpoint="value",outcome="ok"} 1'//lf) > 0, &
               'value ok sample')
    call check(index(reply%body, 'digit_requests_total{digit="2",endpoint="value",outcome="error"} 0'//lf) > 0, &
               'zero sample present')
    call check(index(reply%body, 'digit_build_info{digit="2",version="test"} 1'//lf) > 0, 'build info')
    call store_close(store)
  end subroutine test_metrics

  !> Request lines and headers are parsed; malformed ones are rejected.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_request_parsing()
    !> Carriage return and line feed.
    character(len=2), parameter :: crlf = achar(13)//achar(10)
    character(len=:), allocatable :: method !! Parsed method.
    character(len=:), allocatable :: path !! Parsed path.
    character(len=:), allocatable :: traceparent !! Parsed traceparent.
    logical :: ok !! Outcome of the last step.
    call parse_request('GET /next?x=1 HTTP/1.1'//crlf//'Host: digit-2'//crlf//'TraceParent:  00-ab '//crlf//crlf, &
                       method, path, traceparent, ok)
    call check(ok .and. method == 'GET' .and. path == '/next', 'request line')
    call check(traceparent == '00-ab', 'traceparent header, any case, stripped')
    call parse_request('POST /value HTTP/1.0'//crlf//crlf, method, path, traceparent, ok)
    call check(ok .and. method == 'POST' .and. path == '/value' .and. len(traceparent) == 0, 'no header')
    call parse_request('garbage'//crlf//crlf, method, path, traceparent, ok)
    call check(.not. ok, 'garbage rejected')
    call parse_request('GET value HTTP/1.1'//crlf//crlf, method, path, traceparent, ok)
    call check(.not. ok, 'relative target rejected')
    call parse_request('GET /value HTTP/2.0'//crlf//crlf, method, path, traceparent, ok)
    call check(.not. ok, 'other HTTP version rejected')
  end subroutine test_request_parsing

  !> Responses carry status line, headers and body; HEAD has no body.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_response_format()
    !> Carriage return and line feed.
    character(len=2), parameter :: crlf = achar(13)//achar(10)
    type(reply_t) :: reply !! Reply under test.
    character(len=:), allocatable :: text !! Text under test.
    reply = problem(405, 'Method Not Allowed', 'only GET')
    reply%allow = 'GET'
    text = format_response(reply, .true.)
    call check(text(1:33) == 'HTTP/1.1 405 Method Not Allowed'//crlf, 'status line')
    call check(index(text, 'Allow: GET'//crlf) > 0, 'Allow header')
    call check(index(text, 'Connection: close'//crlf//crlf) > 0, 'Connection close')
    call check(index(text, 'Content-Length: 84'//crlf) > 0, 'content length')
    call check(text(len(text) - len(reply%body) + 1:) == reply%body, 'body last')
    text = format_response(reply, .false.)
    call check(text(len(text) - 3:) == crlf//crlf, 'HEAD without body')
  end subroutine test_response_format

  !> Valid traceparent headers are parsed, invalid ones rejected.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_trace()
    type(trace_context) :: ctx !! Parsed trace context.
    call check(parse_traceparent('00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01', ctx), 'valid header')
    call check(ctx%trace_id == '4bf92f3577b34da6a3ce929d0e0e4736', 'trace id')
    call check(ctx%span_id == '00f067aa0ba902b7', 'span id')
    call check(.not. parse_traceparent('', ctx), 'empty rejected')
    call check(.not. parse_traceparent('00-00000000000000000000000000000000-00f067aa0ba902b7-01', ctx), 'zero id')
    call check(.not. parse_traceparent('00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01', ctx), 'upper case')
    call check(.not. parse_traceparent('ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01', ctx), 'version ff')
    call check(.not. parse_traceparent('00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7', ctx), 'too short')
  end subroutine test_trace

  !> Log lines carry the fields of CLAUDE.md 6.1; escaping, timestamps and
  !> levels.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  subroutine test_log_format()
    character(len=:), allocatable :: line !! Rendered log line.
    call check(json_escape('a"b\c'//achar(10)//'d'//achar(1)) == 'a\"b\\c\nd\u0001', 'json escape')
    call check(format_timestamp(0_int64, 0) == '1970-01-01T00:00:00.000Z', 'epoch')
    call check(format_timestamp(951782400_int64, 5) == '2000-02-29T00:00:00.005Z', 'leap day of a century year')
    call check(format_timestamp(1709208000_int64, 999) == '2024-02-29T12:00:00.999Z', 'leap day')
    call check(format_timestamp(1798761599_int64, 0) == '2026-12-31T23:59:59.000Z', 'end of year')
    line = render_line(level_warn, 'a "quoted" message', '4bf92f3577b34da6a3ce929d0e0e4736', '00f067aa0ba902b7', &
                       'detail')
    call check(index(line, '","level":"warn","service":"digit-2-test","msg":"a \"quoted\" message",'// &
                     '"taskId":null,"traceId":"4bf92f3577b34da6a3ce929d0e0e4736","spanId":"00f067aa0ba902b7",'// &
                     '"detail":"detail"}') > 0, 'full line')
    call check(line(1:7) == '{"ts":"', 'ts first')
    line = render_line(level_info, 'x')
    call check(index(line, '"traceId":null,"spanId":null}') > 0, 'null trace, no detail')
    call check(parse_level('debug', level_info) == level_debug, 'parse debug')
    call check(parse_level('error', level_info) == level_error, 'parse error')
    call check(parse_level('verbose', level_warn) == level_warn, 'unknown level')
    call check(parse_level('', level_info) == level_info, 'unset level')
  end subroutine test_log_format

end program test_digit
