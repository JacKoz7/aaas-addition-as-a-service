#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/main.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Entry point of the digit-9 executable: runs the service
;;                  and exits with its status.
;; Related Docs:    services/digit-9/README.md, src/digit9/service.rkt,
;;                  ADR-0031

;; `raco exe` builds the executable from the `main` submodule; requiring
;; this module (for example from the documentation tools) runs nothing.

;; The executable: runs the service and exits with its status (0 after a
;; graceful stop, 1 when a start-up check fails).
(module+ main
  (require "service.rkt")
  (exit (run)))
