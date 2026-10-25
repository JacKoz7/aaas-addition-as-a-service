#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/trace.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Parsing of the W3C `traceparent` header, so request log
;;                  lines carry the caller's trace and span identifiers.
;; Related Docs:    CLAUDE.md 6.1, https://www.w3.org/TR/trace-context/

;; The service exports no spans before phase 7 (P7.2); it only copies the
;; caller's identifiers into its debug log lines.

(require racket/string)

(provide (struct-out trace-context)
         parse-traceparent)

;; The trace and parent span identifiers of a `traceparent` header.
;;
;; Fields:
;;   - trace-id: string; 32 lower-case hexadecimal digits, not all zero.
;;   - span-id: string; 16 lower-case hexadecimal digits (the caller's
;;     span), not all zero.
;;
;; Business Justification: a request log line names the trace it belongs
;; to, so one addition can be followed across the 35 services.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (trace-context-span-id (trace-context "4bf92f3577b34da6a3ce929d0e0e4736" "00f067aa0ba902b7"))
;;   "00f067aa0ba902b7"
(struct trace-context (trace-id span-id) #:transparent)

;; Parse a `traceparent` header value.
;;
;; Description: the value must be `version-traceid-spanid-flags` with 2,
;; 32, 16 and 2 lower-case hexadecimal digits; version `ff` and all-zero
;; trace or span identifiers are invalid (W3C Trace Context, 3.2).
;;
;; Business Justification: a malformed header from a caller must not put
;; garbage into the log; it is ignored instead.
;;
;; Parameters:
;;   - header: (or/c string? #f); the header value, or #f when absent.
;;
;; Returns: (or/c trace-context? #f); the context, or #f for an absent or
;; invalid header.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (parse-traceparent "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
;;   (trace-context "4bf92f3577b34da6a3ce929d0e0e4736" "00f067aa0ba902b7")
;;   > (parse-traceparent #f)
;;   #f
;;   > (parse-traceparent "garbage")
;;   #f
;;
;; See Also: hex-text?.
(define (parse-traceparent header)
  (define parts (and header (string-split header "-" #:trim? #f)))
  (and parts
       (= (length parts) 4)
       (let ([version (list-ref parts 0)]
             [trace-id (list-ref parts 1)]
             [span-id (list-ref parts 2)]
             [flags (list-ref parts 3)])
         (and (= (string-length version) 2)
              (not (string=? version "ff"))
              (hex-text? version #f)
              (= (string-length trace-id) 32)
              (hex-text? trace-id #t)
              (= (string-length span-id) 16)
              (hex-text? span-id #t)
              (= (string-length flags) 2)
              (hex-text? flags #f)
              (trace-context trace-id span-id)))))

;; Whether a text is lower-case hexadecimal, optionally not all zeros.
;;
;; Parameters:
;;   - part: string; the text.
;;   - non-zero?: boolean; require a digit other than `0`.
;;
;; Returns: boolean; #t when the text qualifies.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (hex-text? "0a" #f)
;;   #t
;;   > (hex-text? "00" #t)
;;   #f
;;   > (hex-text? "0A" #f)
;;   #f
(define (hex-text? part non-zero?)
  (and (for/and ([c (in-string part)])
         (or (char<=? #\0 c #\9) (char<=? #\a c #\f)))
       (or (not non-zero?)
           (for/or ([c (in-string part)])
             (not (char=? c #\0))))))
