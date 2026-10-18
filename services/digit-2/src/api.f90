! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/api.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         The HTTP contract of the digit service as a function
!                  from (method, path) to a reply: routing, JSON bodies,
!                  problem details, health and metrics.
! Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

!> Request handling of contracts/http/digit.yaml, independent of the
!> HTTP server.
!>
!> **Description:** The server ([[digit_http]]) passes each request to
!> [[api_handle]] and sends the reply it returns; the unit tests call
!> [[api_handle]] directly.
!>
!> **Business Justification:** The single implementation of the contract
!> that every digit request goes through; the value is read on every
!> request, never cached or hard-coded (CLAUDE.md 4.4).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_store]], [[digit_metrics]]
module digit_api
  use digit_store, only: store_t, digit_row, store_read
  use digit_metrics, only: metrics_t, metrics_count, metrics_render, endpoint_value, endpoint_next, outcome_ok, &
                           outcome_error
  use digit_log, only: log_write, level_error, json_escape
  implicit none
  private

  public :: reply_t, api_handle, problem

  !> Media type of JSON bodies.
  character(len=*), parameter :: json_type = 'application/json'
  !> Media type of problem details (RFC 9457).
  character(len=*), parameter :: problem_type = 'application/problem+json'
  !> Media type of the Prometheus text exposition.
  character(len=*), parameter :: prometheus_type = 'text/plain; version=0.0.4'

  !> An HTTP reply to send.
  type :: reply_t
    !> HTTP status code.
    integer :: status = 0
    !> Value of Content-Type.
    character(len=:), allocatable :: content_type
    !> Value of Allow; empty when not sent (405 only).
    character(len=:), allocatable :: allow
    !> Response body.
    character(len=:), allocatable :: body
  end type reply_t

contains

  !> Answer one request according to contracts/http/digit.yaml.
  !>
  !> **Description:** `GET /value` → 200 `{"digit":d,"value":v}`;
  !> `GET /next` → 200 `{"digit":d,"next":n,"carry":c}`, both from the
  !> database; `GET /health` → 200 `{"status":"ok","checks":{"database":"ok"}}`
  !> when the row can be read and names the configured digit, otherwise 503
  !> with `error`; `GET /metrics` → 200 Prometheus text; another method on
  !> one of these paths → 405 problem with `Allow: GET`; any other path →
  !> 404 problem. When the row cannot be read or names another digit,
  !> `/value` and `/next` answer 503 problem details and count an error.
  !>
  !> **Business Justification:** The arithmetic of the digit (CLAUDE.md 4.4).
  !>
  !> **Returns:** The reply. **Errors:** None (404, 405 or 503 replies).
  !> **Side Effects:** Reads the database; updates the metrics; logs
  !> database failures.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `reply = api_handle(st, 2, m, 'GET', '/next')` gives
  !> `{"digit":2,"next":3,"carry":false}`.
  !>
  !> **See Also:** [[store_read]], [[metrics_render]]
  function api_handle(store, digit, metrics, method, path) result(reply)
    !> Open, migrated database of the service.
    type(store_t), intent(in) :: store
    !> The digit the service represents (AAAS_DIGIT).
    integer, intent(in) :: digit
    !> Counters updated by /value and /next.
    type(metrics_t), intent(inout) :: metrics
    !> HTTP method, upper case.
    character(len=*), intent(in) :: method
    !> Request path without the query string.
    character(len=*), intent(in) :: path
    !> The reply.
    type(reply_t) :: reply
    type(digit_row) :: row !! The digit row.
    logical :: ok !! Outcome of the last step.

    if (path /= '/value' .and. path /= '/next' .and. path /= '/health' .and. path /= '/metrics') then
      reply = problem(404, 'Not Found', 'the digit service has no such path')
    else if (method /= 'GET') then
      reply = problem(405, 'Method Not Allowed', 'only GET is allowed on this path')
      reply%allow = 'GET'
    else if (path == '/value' .or. path == '/next') then
      reply = answer_digit(store, digit, metrics, path == '/next')
    else if (path == '/health') then
      ok = read_row(store, digit, row)
      reply%status = merge(200, 503, ok)
      reply%content_type = json_type
      reply%allow = ''
      reply%body = '{"status":"'//trim(merge('ok   ', 'error', ok))//'","checks":{"database":"'// &
                   trim(merge('ok   ', 'error', ok))//'"}}'
    else
      reply%status = 200
      reply%content_type = prometheus_type
      reply%allow = ''
      reply%body = metrics_render(metrics)
    end if
  end function api_handle

  !> Answer GET /value or GET /next.
  !>
  !> **Description:** Reads the row on every call; 503 problem details when
  !> it cannot be read. Counts the request in the metrics.
  !>
  !> **Business Justification:** The arithmetic of the digit (CLAUDE.md 4.4).
  !>
  !> **Returns:** The reply. **Errors:** None (503 reply on failure).
  !> **Side Effects:** One SELECT; one counter increment.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `reply = answer_digit(st, 2, m, .true.)`
  !>
  !> **See Also:** [[api_handle]]
  function answer_digit(store, digit, metrics, next) result(reply)
    !> Database of the service.
    type(store_t), intent(in) :: store
    !> The configured digit.
    integer, intent(in) :: digit
    !> Counters.
    type(metrics_t), intent(inout) :: metrics
    !> True for /next, false for /value.
    logical, intent(in) :: next
    !> The reply.
    type(reply_t) :: reply
    type(digit_row) :: row !! The digit row.
    integer :: endpoint !! Endpoint index of the request.

    endpoint = merge(endpoint_next, endpoint_value, next)
    if (.not. read_row(store, digit, row)) then
      call metrics_count(metrics, endpoint, outcome_error)
      reply = problem(503, 'Service Unavailable', 'the digit cannot be read from the database; retry the call')
      return
    end if
    call metrics_count(metrics, endpoint, outcome_ok)
    reply%status = 200
    reply%content_type = json_type
    reply%allow = ''
    if (next) then
      reply%body = '{"digit":'//itoa(row%digit)//',"next":'//itoa(row%next)//',"carry":'// &
                   trim(merge('true ', 'false', row%carry))//'}'
    else
      reply%body = '{"digit":'//itoa(row%digit)//',"value":'//itoa(row%value)//'}'
    end if
  end function answer_digit

  !> Read the digit row and check that it names the configured digit.
  !>
  !> **Description:** Read failures are logged by [[store_read]]; a row of
  !> another digit is logged here.
  !>
  !> **Business Justification:** A service must never answer for another
  !> digit, for example after its volume was mixed up with another one's.
  !>
  !> **Returns:** True when the row was read and matches the digit.
  !> **Errors:** False on failure. **Side Effects:** One SELECT; logs.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `if (read_row(st, 2, row)) ...`
  !>
  !> **See Also:** [[store_read]]
  function read_row(store, digit, row) result(ok)
    !> Database of the service.
    type(store_t), intent(in) :: store
    !> The configured digit.
    integer, intent(in) :: digit
    !> Receives the row.
    type(digit_row), intent(inout) :: row
    !> True when the row is usable.
    logical :: ok
    character(len=:), allocatable :: message !! Reason of a failure.
    call store_read(store, row, ok, message)
    if (ok .and. row%digit /= digit) then
      call log_write(level_error, 'the database holds another digit')
      ok = .false.
    end if
  end function read_row

  !> Build a problem details reply (RFC 9457).
  !>
  !> **Description:** `type` is `about:blank`; `detail` is JSON-escaped.
  !>
  !> **Business Justification:** Every AaaS error is problem details
  !> (CLAUDE.md 4.1).
  !>
  !> **Returns:** The reply with Content-Type `application/problem+json`.
  !> **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(n). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `reply = problem(404, 'Not Found', 'no such path')`
  !>
  !> **See Also:** [[api_handle]]
  function problem(status, title, detail) result(reply)
    !> HTTP status.
    integer, intent(in) :: status
    !> Short summary of the problem type.
    character(len=*), intent(in) :: title
    !> Explanation of this occurrence.
    character(len=*), intent(in) :: detail
    !> The reply.
    type(reply_t) :: reply
    reply%status = status
    reply%content_type = problem_type
    reply%allow = ''
    reply%body = '{"type":"about:blank","title":"'//json_escape(title)//'","status":'//itoa(status)// &
                 ',"detail":"'//json_escape(detail)//'"}'
  end function problem

  !> Decimal text of an integer.
  !>
  !> **Description:** No padding, a minus sign for negative values.
  !>
  !> **Business Justification:** JSON numbers of the bodies.
  !>
  !> **Returns:** The digits. **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Safe.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `itoa(503)` is `503`.
  !>
  !> **See Also:** [[problem]]
  pure function itoa(number) result(text)
    !> The number.
    integer, intent(in) :: number
    !> Its decimal text.
    character(len=:), allocatable :: text
    character(len=12) :: buffer !! Formatting buffer.
    write (buffer, '(i0)') number
    text = trim(buffer)
  end function itoa

end module digit_api
