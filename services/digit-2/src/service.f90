! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/service.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         The digit-2 service: configuration from the
!                  environment, database migrations, the HTTP server on
!                  port 8080 and graceful shutdown.
! Related Docs:    services/digit-2/README.md, CLAUDE.md 4.4, 6.1,
!                  ADR-0022, ADR-0024

!> The digit-2 service: configuration, start-up and shutdown.
!>
!> **Description:** Reads the configuration (AAAS_BOOTSTRAP=env until
!> P5.2), opens and migrates the database, checks that it holds the
!> configured digit, then serves HTTP until SIGTERM or SIGINT and closes
!> the database, well within the 10 s of CLAUDE.md 6.1. Exits with status 1
!> when start-up fails.
!>
!> The state of the process (configuration, database, counters) lives in
!> private module variables, so that the request handler passed to the
!> server is a module procedure and needs no trampoline (no executable
!> stack).
!>
!> **Business Justification:** Digit 2 as a service (CLAUDE.md 2, row 15).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_http]], [[digit_api]]
module digit_service
  use, intrinsic :: iso_c_binding, only: c_int
  use digit_posix, only: install_stop_handlers, stop_signal, c_exit
  use digit_log
  use digit_store
  use digit_metrics, only: metrics_t, metrics_init
  use digit_api, only: reply_t, api_handle
  use digit_trace, only: trace_context, parse_traceparent
  use digit_http, only: http_serve
  implicit none
  private

  public :: service_main

  !> Version of the service (SemVer, docs/CHANGELOG.md).
  character(len=*), parameter :: service_version = '0.1.0'
  !> AAAS_DB_PATH (default `/data/digit-2.db`).
  character(len=:), allocatable :: db_path
  !> AAAS_MIGRATIONS_DIR (default `/app/migrations`).
  character(len=:), allocatable :: migrations_dir
  !> AAAS_DIGIT, 0..9 (default 2).
  integer :: digit
  !> AAAS_HTTP_PORT (default 8080).
  integer :: port
  !> The database of the service.
  type(store_t) :: store
  !> Request counters.
  type(metrics_t) :: metrics

contains

  !> Run the service until SIGTERM or SIGINT.
  !>
  !> **Description:** Reads the configuration, opens and migrates the
  !> database, checks the row against AAAS_DIGIT, serves HTTP, then closes
  !> the database. Exits the process with status 1 when start-up fails.
  !>
  !> **Business Justification:** Digit 2 as a service (CLAUDE.md 2, row 15).
  !>
  !> **Errors:** Status 1 for invalid configuration, an unopenable or
  !> unmigratable database, a database holding another digit, or a port that
  !> cannot be bound. **Side Effects:** Database, network, logs.
  !>
  !> **Complexity:** Not applicable. **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call service_main()` from the program `digit_2`.
  !>
  !> **See Also:** [[http_serve]], [[api_handle]]
  subroutine service_main()
    type(digit_row) :: row !! The row read at start-up.
    logical :: ok !! Outcome of the last step.
    character(len=:), allocatable :: message !! Reason of the last failure.
    integer :: applied !! Migrations applied at start-up.

    call log_init(env('AAAS_SERVICE', 'digit-2'), parse_level(env('AAAS_LOG_LEVEL', ''), level_info))
    call load_config(ok)
    if (.not. ok) call c_exit(1_c_int)

    call store_open(store, db_path, ok, message)
    if (ok) call store_migrate(store, migrations_dir, applied, ok, message)
    if (.not. ok) call fail('the database cannot be prepared', message)
    call store_read(store, row, ok, message)
    if (.not. ok .or. row%digit /= digit) call fail('the database does not hold the configured digit', db_path)

    call metrics_init(metrics, digit, service_version)
    call install_stop_handlers()
    call http_serve(port, handle, announce, ok)
    if (.not. ok) call fail('cannot start the HTTP server', 'port '//itoa(port))

    if (stop_signal == 15) then
      call log_write(level_info, 'shutting down', detail='SIGTERM')
    else
      call log_write(level_info, 'shutting down', detail='SIGINT')
    end if
    call store_close(store)
    call log_write(level_info, 'stopped')
  end subroutine service_main

  !> Value of an environment variable, or a default when unset or empty.
  !>
  !> **Description:** Thin wrapper over `get_environment_variable`.
  !>
  !> **Business Justification:** Configuration comes only from the
  !> environment (CLAUDE.md 6.1).
  !>
  !> **Returns:** The value. **Errors:** None. **Side Effects:** Reads the
  !> environment.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `path = env('AAAS_DB_PATH', '/data/digit-2.db')`
  !>
  !> **See Also:** [[load_config]]
  function env(name, fallback) result(value)
    !> Variable name.
    character(len=*), intent(in) :: name
    !> Value used when the variable is unset or empty.
    character(len=*), intent(in) :: fallback
    !> The value.
    character(len=:), allocatable :: value
    integer :: length !! Length of the value.
    integer :: status !! I/O or environment status code.
    call get_environment_variable(name, length=length, status=status)
    if (status /= 0 .or. length == 0) then
      value = fallback
      return
    end if
    allocate (character(len=length) :: value)
    call get_environment_variable(name, value)
  end function env

  !> Parse a decimal integer in [low, high].
  !>
  !> **Description:** The whole text must be digits.
  !>
  !> **Business Justification:** Rejects misconfiguration (a port of 0) at
  !> start-up.
  !>
  !> **Returns:** `ok` false for non-numeric text or a value out of range.
  !> **Errors:** See Returns. **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call parse_int('8080', 1, 65535, port, ok)`
  !>
  !> **See Also:** [[load_config]]
  subroutine parse_int(text, low, high, value, ok)
    !> Text to parse.
    character(len=*), intent(in) :: text
    !> Smallest accepted value.
    integer, intent(in) :: low
    !> Largest accepted value.
    integer, intent(in) :: high
    !> The value on success.
    integer, intent(out) :: value
    !> True on success.
    logical, intent(out) :: ok
    integer :: status !! I/O or environment status code.
    value = 0
    ok = len(text) > 0 .and. len(text) <= 9 .and. verify(text, '0123456789') == 0
    if (.not. ok) return
    read (text, '(i9)', iostat=status) value
    ok = status == 0 .and. value >= low .and. value <= high
  end subroutine parse_int

  !> Read the configuration from the environment.
  !>
  !> **Description:** Only AAAS_BOOTSTRAP=env is available until the config
  !> server and OpenBao exist (P5.2, P5.3); `platform` is refused.
  !>
  !> **Business Justification:** CLAUDE.md 3 and 6.1.
  !>
  !> **Returns:** `ok` false for an unsupported AAAS_BOOTSTRAP or an invalid
  !> AAAS_DIGIT or AAAS_HTTP_PORT (logged). **Errors:** See Returns.
  !> **Side Effects:** Reads the environment; logs errors; sets the program
  !> variables.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Call once at start-up.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call load_config(ok)`
  !>
  !> **See Also:** [[env]]
  subroutine load_config(ok)
    !> True when the configuration is valid.
    logical, intent(out) :: ok
    character(len=:), allocatable :: bootstrap !! Value of AAAS_BOOTSTRAP.
    character(len=:), allocatable :: text !! Raw value of the variable being parsed.
    bootstrap = env('AAAS_BOOTSTRAP', 'env')
    ok = bootstrap == 'env'
    if (.not. ok) then
      call log_write(level_error, 'unsupported AAAS_BOOTSTRAP; only env exists before P5.2', detail=bootstrap)
      return
    end if
    text = env('AAAS_DIGIT', '2')
    call parse_int(text, 0, 9, digit, ok)
    if (.not. ok) then
      call log_write(level_error, 'AAAS_DIGIT must be 0..9', detail=text)
      return
    end if
    text = env('AAAS_HTTP_PORT', '8080')
    call parse_int(text, 1, 65535, port, ok)
    if (.not. ok) then
      call log_write(level_error, 'AAAS_HTTP_PORT must be 1..65535', detail=text)
      return
    end if
    db_path = env('AAAS_DB_PATH', '/data/digit-2.db')
    migrations_dir = env('AAAS_MIGRATIONS_DIR', '/app/migrations')
  end subroutine load_config

  !> Log a start-up failure, close the database and exit with status 1.
  !>
  !> **Description:** Does not return.
  !>
  !> **Business Justification:** A misconfigured service must not serve.
  !>
  !> **Errors:** None. **Side Effects:** Logs; closes the database; exits.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call fail('cannot start the HTTP server', 'port 8080')`
  !>
  !> **See Also:** [[c_exit]]
  subroutine fail(msg, detail)
    !> Message, English.
    character(len=*), intent(in) :: msg
    !> Detail (reason, path or port).
    character(len=*), intent(in) :: detail
    call log_write(level_error, msg, detail=detail)
    call store_close(store)
    call c_exit(1_c_int)
  end subroutine fail

  !> Log that the server listens.
  !>
  !> **Description:** Called by [[http_serve]] once the port is bound.
  !>
  !> **Business Justification:** Operators see when the service is ready.
  !>
  !> **Errors:** None. **Side Effects:** Writes a log line.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** passed to [[http_serve]].
  !>
  !> **See Also:** [[http_serve]]
  subroutine announce()
    call log_write(level_info, 'listening', detail='port '//itoa(port)//', digit '//itoa(digit)//', version '// &
                   service_version)
  end subroutine announce

  !> Answer one request through the contract and log it at debug level.
  !>
  !> **Description:** The debug line carries the caller's trace when the
  !> `traceparent` header is valid.
  !>
  !> **Business Justification:** Bridges the server to the contract code.
  !>
  !> **Errors:** None. **Side Effects:** Database read, metrics, debug log.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** passed to [[http_serve]].
  !>
  !> **See Also:** [[api_handle]]
  subroutine handle(method, path, traceparent, reply)
    !> HTTP method.
    character(len=*), intent(in) :: method
    !> Path without the query string.
    character(len=*), intent(in) :: path
    !> Value of `traceparent`, empty when absent.
    character(len=*), intent(in) :: traceparent
    !> The reply.
    type(reply_t), intent(out) :: reply
    type(trace_context) :: trace !! Caller trace context.
    character(len=:), allocatable :: detail !! Detail of the debug line.
    reply = api_handle(store, digit, metrics, method, path)
    detail = method//' '//path//' -> '//itoa(reply%status)
    if (parse_traceparent(traceparent, trace)) then
      call log_write(level_debug, 'request answered', trace%trace_id, trace%span_id, detail)
    else
      call log_write(level_debug, 'request answered', detail=detail)
    end if
  end subroutine handle

  !> Decimal text of an integer.
  !>
  !> **Description:** No padding.
  !>
  !> **Business Justification:** Log details.
  !>
  !> **Returns:** The digits. **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `itoa(8080)` is `8080`.
  !>
  !> **See Also:** [[announce]]
  pure function itoa(number) result(text)
    !> The number.
    integer, intent(in) :: number
    !> Its decimal text.
    character(len=:), allocatable :: text
    character(len=12) :: buffer !! Formatting buffer.
    write (buffer, '(i0)') number
    text = trim(buffer)
  end function itoa

end module digit_service
