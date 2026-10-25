#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/metrics.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Prometheus metrics of the digit service: the request
;;                  counter shared by all ten digit services and the build
;;                  information.
;; Related Docs:    contracts/http/digit.yaml (GET /metrics), ADR-0021

(provide (struct-out metrics)
         make-metrics
         metrics-count!
         metrics-get
         metrics-render)

;; The arithmetic endpoints, values of the `endpoint` label, in the order
;; of the exposition.
(define endpoints '(value next))

;; The outcomes of a request, values of the `outcome` label: `ok` (answered
;; 200) and `error` (answered 503, database unavailable).
(define outcomes '(ok error))

;; Counters of one service process; every sample exists from the start
;; (value 0).
;;
;; Fields:
;;   - digit: exact-nonnegative-integer; the value of the `digit` label,
;;     0..9.
;;   - version: string; the service version for `digit_build_info`.
;;   - counts: (vectorof exact-nonnegative-integer?); the
;;     `digit_requests_total` samples, endpoint-major (see sample-index).
;;
;; Business Justification: one dashboard shows the traffic of all ten
;; digit services (P7.3).
;;
;; Thread Safety: not synchronised; used only through the contract, which
;; the server calls under one lock (ADR-0031).
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (metrics-version (make-metrics 9 "0.1.0"))
;;   "0.1.0"
(struct metrics (digit version counts))

;; Create zeroed counters.
;;
;; Business Justification: every sample of `digit_requests_total` exists
;; from the start, so dashboards show 0 instead of no data.
;;
;; Parameters:
;;   - digit: exact-nonnegative-integer; the service's digit, 0..9.
;;   - version: string; the service version.
;;
;; Returns: metrics; four samples at 0.
;;
;; Errors: none. Side Effects: allocates. Complexity: O(1).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (metrics-get (make-metrics 9 "0.1.0") 'next 'ok)
;;   0
(define (make-metrics digit version)
  (metrics digit version (make-vector (* (length endpoints) (length outcomes)) 0)))

;; The position of a sample in the counts vector.
;;
;; Parameters:
;;   - endpoint: symbol; `value` or `next`.
;;   - outcome: symbol; `ok` or `error`.
;;
;; Returns: exact-nonnegative-integer; 0..3.
;;
;; Errors: raises exn:fail:contract when a label is unknown (a programming
;; error). Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (sample-index 'next 'error)
;;   3
(define (sample-index endpoint outcome)
  (+ (* (label-index endpoint endpoints) (length outcomes)) (label-index outcome outcomes)))

;; The position of a label value in its list.
;;
;; Parameters:
;;   - value: symbol; the label value.
;;   - values: (listof symbol?); the label's values.
;;
;; Returns: exact-nonnegative-integer; the position.
;;
;; Errors: raises exn:fail:contract when `value` is not in `values`.
;; Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (label-index 'error outcomes)
;;   1
(define (label-index value values)
  (or (for/first ([candidate (in-list values)]
                  [index (in-naturals)]
                  #:when (eq? candidate value))
        index)
      (raise-argument-error 'label-index (format "one of ~a" values) value)))

;; Count one answered request.
;;
;; Business Justification: traffic and errors per digit.
;;
;; Parameters:
;;   - counters: metrics; the counters.
;;   - endpoint: symbol; the endpoint answered, `value` or `next`.
;;   - outcome: symbol; the outcome, `ok` or `error`.
;;
;; Returns: void.
;;
;; Errors: raises exn:fail:contract for an unknown label. Side Effects:
;; increments one counter. Complexity: O(1). Thread Safety: under the
;; server's lock. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define counters (make-metrics 9 "0.1.0"))
;;   > (metrics-count! counters 'next 'ok)
;;   > (metrics-get counters 'next 'ok)
;;   1
(define (metrics-count! counters endpoint outcome)
  (define index (sample-index endpoint outcome))
  (define counts (metrics-counts counters))
  (vector-set! counts index (add1 (vector-ref counts index))))

;; Current value of one sample.
;;
;; Business Justification: the unit tests read single samples.
;;
;; Parameters:
;;   - counters: metrics; the counters.
;;   - endpoint: symbol; `value` or `next`.
;;   - outcome: symbol; `ok` or `error`.
;;
;; Returns: exact-nonnegative-integer; the number of counted requests.
;;
;; Errors: raises exn:fail:contract for an unknown label. Side Effects:
;; none. Complexity: O(1). Thread Safety: under the server's lock.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (metrics-get (make-metrics 9 "0.1.0") 'value 'error)
;;   0
(define (metrics-get counters endpoint outcome)
  (vector-ref (metrics-counts counters) (sample-index endpoint outcome)))

;; Render the Prometheus text exposition (format 0.0.4).
;;
;; Description: `digit_requests_total` with the labels digit, endpoint and
;; outcome (all four samples) and `digit_build_info` with the labels digit
;; and version, value 1.
;;
;; Business Justification: GET /metrics of the contract.
;;
;; Parameters:
;;   - counters: metrics; the counters.
;;
;; Returns: string; the exposition text.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
;; under the server's lock. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (regexp-match? #rx"digit_build_info{digit=\"9\",version=\"0.1.0\"} 1\n$"
;;                    (metrics-render (make-metrics 9 "0.1.0")))
;;   #t
(define (metrics-render counters)
  (define out (open-output-string))
  (define digit (number->string (metrics-digit counters)))
  (write-string "# HELP digit_requests_total Requests answered by the digit service.\n" out)
  (write-string "# TYPE digit_requests_total counter\n" out)
  (for* ([endpoint (in-list endpoints)]
         [outcome (in-list outcomes)])
    (write-string (string-append "digit_requests_total{digit=\""
                                 digit
                                 "\",endpoint=\""
                                 (symbol->string endpoint)
                                 "\",outcome=\""
                                 (symbol->string outcome)
                                 "\"} "
                                 (number->string (metrics-get counters endpoint outcome))
                                 "\n")
                  out))
  (write-string "# HELP digit_build_info Build information of the digit service.\n" out)
  (write-string "# TYPE digit_build_info gauge\n" out)
  (write-string (string-append "digit_build_info{digit=\""
                               digit
                               "\",version=\""
                               (metrics-version counters)
                               "\"} 1\n")
                out)
  (get-output-string out))
