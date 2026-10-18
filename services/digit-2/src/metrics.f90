! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/metrics.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         Prometheus metrics of the digit service: the request
!                  counter shared by all ten digit services and the build
!                  information.
! Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

!> Request counter `digit_requests_total` and its exposition.
!>
!> **Description:** Counters per endpoint (`value`, `next`) and outcome
!> (`ok`, `error`), all four samples present from the start.
!>
!> **Business Justification:** One dashboard shows the traffic of all ten
!> digit services (P7.3).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_api]]
module digit_metrics
  use, intrinsic :: iso_fortran_env, only: int64
  implicit none
  private

  public :: endpoint_value, endpoint_next, outcome_ok, outcome_error
  public :: metrics_t, metrics_init, metrics_count, metrics_render

  !> Endpoint index of GET /value.
  integer, parameter :: endpoint_value = 1
  !> Endpoint index of GET /next.
  integer, parameter :: endpoint_next = 2
  !> Outcome index of a 200 answer.
  integer, parameter :: outcome_ok = 1
  !> Outcome index of a 503 answer (database unavailable).
  integer, parameter :: outcome_error = 2
  !> Values of the `endpoint` label, by endpoint index.
  character(len=5), parameter :: endpoint_names(2) = ['value', 'next ']
  !> Values of the `outcome` label, by outcome index.
  character(len=5), parameter :: outcome_names(2) = ['ok   ', 'error']

  !> Counters of one service process.
  type :: metrics_t
    !> Value of the `digit` label, 0..9.
    integer :: digit = 0
    !> Service version for `digit_build_info`.
    character(len=16) :: version = ''
    !> `digit_requests_total` samples by endpoint and outcome.
    integer(int64) :: requests(2, 2) = 0_int64
  end type metrics_t

contains

  !> Initialise the counters of a service.
  !>
  !> **Description:** Sets every counter to zero.
  !>
  !> **Business Justification:** Every sample of the contract exists from
  !> the start (value 0).
  !>
  !> **Errors:** None. **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call metrics_init(m, 2, '0.1.0')`
  !>
  !> **See Also:** [[metrics_count]]
  subroutine metrics_init(metrics, digit, version)
    !> Counters to initialise.
    type(metrics_t), intent(out) :: metrics
    !> The service's digit.
    integer, intent(in) :: digit
    !> Service version.
    character(len=*), intent(in) :: version
    metrics%digit = digit
    metrics%version = version
    metrics%requests = 0_int64
  end subroutine metrics_init

  !> Count one answered request.
  !>
  !> **Description:** Out-of-range indices are ignored.
  !>
  !> **Business Justification:** Traffic and errors per digit.
  !>
  !> **Errors:** None. **Side Effects:** Increments one counter.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `call metrics_count(m, endpoint_next, outcome_ok)`
  !>
  !> **See Also:** [[metrics_render]]
  subroutine metrics_count(metrics, endpoint, outcome)
    !> Counters.
    type(metrics_t), intent(inout) :: metrics
    !> Endpoint index.
    integer, intent(in) :: endpoint
    !> Outcome index.
    integer, intent(in) :: outcome
    if (endpoint < 1 .or. endpoint > 2 .or. outcome < 1 .or. outcome > 2) return
    metrics%requests(endpoint, outcome) = metrics%requests(endpoint, outcome) + 1_int64
  end subroutine metrics_count

  !> Render the Prometheus text exposition (format 0.0.4).
  !>
  !> **Description:** `digit_requests_total{digit,endpoint,outcome}` (all
  !> four samples) and `digit_build_info{digit,version} 1`.
  !>
  !> **Business Justification:** GET /metrics of the contract.
  !>
  !> **Returns:** The exposition text. **Errors:** None.
  !> **Side Effects:** None.
  !>
  !> **Complexity:** O(1). **Thread Safety:** Single-threaded service.
  !>
  !> **Owner:** Arithmetic Excellence Center (AEC). **Since:** digit-2 0.1.0
  !>
  !> **Example:** `text = metrics_render(m)`
  !>
  !> **See Also:** [[metrics_count]]
  function metrics_render(metrics) result(text)
    !> Counters.
    type(metrics_t), intent(in) :: metrics
    !> The exposition.
    character(len=:), allocatable :: text
    character(len=20) :: number !! Formatting buffer for a number.
    character(len=:), allocatable :: digit !! The digit label as text.
    integer :: e !! Endpoint index.
    integer :: o !! Outcome index.
    write (number, '(i0)') metrics%digit
    digit = trim(number)
    text = '# HELP digit_requests_total Requests answered by the digit service.'//new_line('a')// &
           '# TYPE digit_requests_total counter'//new_line('a')
    do e = 1, 2
      do o = 1, 2
        write (number, '(i0)') metrics%requests(e, o)
        text = text//'digit_requests_total{digit="'//digit//'",endpoint="'//trim(endpoint_names(e))// &
               '",outcome="'//trim(outcome_names(o))//'"} '//trim(number)//new_line('a')
      end do
    end do
    text = text//'# HELP digit_build_info Build information of the digit service.'//new_line('a')// &
           '# TYPE digit_build_info gauge'//new_line('a')// &
           'digit_build_info{digit="'//digit//'",version="'//trim(metrics%version)//'"} 1'//new_line('a')
  end function metrics_render

end module digit_metrics
