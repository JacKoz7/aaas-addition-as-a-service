! SPDX-License-Identifier: MIT
! Copyright (c) 2026 AaaS Contributors
!
! Component:       digit-2
! Module:          src/main.f90
! Owning Team:     Arithmetic Excellence Center (AEC)
! Classification:  INTERNAL
! Purpose:         Entry point of the digit-2 service.
! Related Docs:    src/service.f90, services/digit-2/README.md, ADR-0024

!> Process entry point of digit-2.
!>
!> **Description:** Runs [[service_main]]; the exit status is 0 after a
!> graceful stop and 1 when start-up fails.
!>
!> **Business Justification:** Digit 2 as a service (CLAUDE.md 2, row 15).
!>
!> **Owner:** Arithmetic Excellence Center (AEC)
!>
!> **Since:** digit-2 0.1.0
!>
!> **See Also:** [[digit_service]]
program digit_2
  use digit_service, only: service_main
  implicit none
  call service_main()
end program digit_2
