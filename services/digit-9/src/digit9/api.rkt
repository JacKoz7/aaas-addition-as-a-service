#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/api.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         The HTTP contract of the digit service as a function
;;                  from (method, path) to a reply: routing, JSON bodies,
;;                  problem details, health and metrics.
;; Related Docs:    contracts/http/digit.yaml, ADR-0021, ADR-0022

(require "log.rkt"
         "metrics.rkt"
         "store.rkt")

(provide json-type
         problem-type
         prometheus-type
         (struct-out reply)
         problem
         (struct-out api)
         api-handle)

;; Media type of JSON bodies.
(define json-type "application/json")

;; Media type of problem details (RFC 9457).
(define problem-type "application/problem+json")

;; Media type of the Prometheus text exposition.
(define prometheus-type "text/plain; version=0.0.4")

;; Paths of the contract.
(define contract-paths '("/value" "/next" "/health" "/metrics"))

;; An HTTP reply to send.
;;
;; Fields:
;;   - status: exact-integer; the HTTP status code.
;;   - content-type: string; the value of Content-Type.
;;   - body: string; the response body.
;;   - allow: (or/c string? #f); the value of Allow, or #f when not sent
;;     (405 only).
;;
;; Business Justification: the contract is a pure function to this value,
;; so it is tested without a socket.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reply-status (reply 200 json-type "{}" #f))
;;   200
(struct reply (status content-type body allow) #:transparent)

;; Build a problem details reply (RFC 9457).
;;
;; Description: `type` is `about:blank`; the title and the detail are
;; JSON-escaped.
;;
;; Business Justification: every AaaS error is problem details
;; (CLAUDE.md 4.1).
;;
;; Parameters:
;;   - status: exact-integer; the HTTP status.
;;   - title: string; a short summary of the problem type.
;;   - detail: string; an explanation of this occurrence.
;;   - allow: (or/c string? #f); the value of Allow, for 405; #f by
;;     default.
;;
;; Returns: reply; the reply with Content-Type `application/problem+json`.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reply-body (problem 404 "Not Found" "no \"x\""))
;;   "{\"type\":\"about:blank\",\"title\":\"Not Found\",\"status\":404,\"detail\":\"no \\\"x\\\"\"}"
;;   > (reply-content-type (problem 404 "Not Found" "no such path"))
;;   "application/problem+json"
;;
;; See Also: api-handle.
(define (problem status title detail [allow #f])
  (reply status
         problem-type
         (string-append "{\"type\":\"about:blank\",\"title\":\""
                        (json-escape title)
                        "\",\"status\":"
                        (number->string status)
                        ",\"detail\":\""
                        (json-escape detail)
                        "\"}")
         allow))

;; The digit contract over one database.
;;
;; Fields:
;;   - store: store; the open, migrated database of the service.
;;   - digit: exact-integer; the digit the service represents, 0..9
;;     (`AAAS_DIGIT`).
;;   - metrics: metrics; the counters updated by /value and /next.
;;   - log: logger; the logger for database failures.
;;
;; Business Justification: the single implementation of the contract that
;; every digit request goes through; the value is read on every request,
;; never cached or hard-coded (CLAUDE.md 4.4).
;;
;; Thread Safety: not synchronised; the server calls it under one lock,
;; which also covers the store and the metrics it holds (ADR-0031).
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (define contract (api db 9 (make-metrics 9 "0.1.0") log))
(struct api (store digit metrics log))

;; Read the digit row and check that it names the configured digit.
;;
;; Description: a failure is logged at error level.
;;
;; Business Justification: a service must never answer for another digit,
;; for example after its volume was mixed up with another one.
;;
;; Parameters:
;;   - contract: api; the contract.
;;
;; Returns: (or/c digit-row? #f); the row, or #f on failure.
;;
;; Errors: none (#f). Side Effects: one SELECT; logs failures.
;; Complexity: O(1). Thread Safety: under the server's lock.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (read-row contract) ; (digit-row 9 9 0 #t)
;;
;; See Also: store-read.
(define (read-row contract)
  (define log (api-log contract))
  (define row
    (with-handlers
        ([exn:fail:store?
          (lambda (error)
            (log-write! log 'error "cannot read the digit from the database" (exn-message error))
            #f)])
      (store-read (api-store contract))))
  (cond
    [(not row) #f]
    [(= (digit-row-digit row) (api-digit contract)) row]
    [else
     (log-write! log 'error "the database holds another digit")
     #f]))

;; Answer GET /value or GET /next.
;;
;; Description: reads the row on every call; 503 problem details when it
;; cannot be read. Counts the request in the metrics.
;;
;; Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).
;;
;; Parameters:
;;   - contract: api; the contract.
;;   - endpoint: symbol; `value` or `next`.
;;
;; Returns: reply; the reply.
;;
;; Errors: none (503 reply). Side Effects: one SELECT; one counter
;; increment. Complexity: O(1). Thread Safety: under the server's lock.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (answer-digit contract 'next) ; {"digit":9,"next":0,"carry":true}
(define (answer-digit contract endpoint)
  (define row (read-row contract))
  (define counters (api-metrics contract))
  (cond
    [(not row)
     (metrics-count! counters endpoint 'error)
     (problem 503
              "Service Unavailable"
              "the digit cannot be read from the database; retry the call")]
    [else
     (metrics-count! counters endpoint 'ok)
     (define digit (number->string (digit-row-digit row)))
     (reply 200
            json-type
            (if (eq? endpoint 'value)
                (string-append "{\"digit\":"
                               digit
                               ",\"value\":"
                               (number->string (digit-row-value row))
                               "}")
                (string-append "{\"digit\":"
                               digit
                               ",\"next\":"
                               (number->string (digit-row-next row))
                               ",\"carry\":"
                               (if (digit-row-carry row) "true" "false")
                               "}"))
            #f)]))

;; Answer one request according to contracts/http/digit.yaml.
;;
;; Description: GET /value answers 200 with digit and value; GET /next 200
;; with digit, next and carry, both from the database; GET /health 200
;; with status ok and checks.database ok when the row can be read and
;; names the configured digit, otherwise 503 with error; GET /metrics 200
;; Prometheus text; another method on one of these paths 405 problem
;; details with Allow: GET; any other path 404 problem details. When the
;; row cannot be read or names another digit, /value and /next answer 503
;; problem details and count an error.
;;
;; Business Justification: the arithmetic of the digit (CLAUDE.md 4.4).
;;
;; Parameters:
;;   - contract: api; the contract.
;;   - method: string; the HTTP method, as received.
;;   - path: string; the request path without the query string.
;;
;; Returns: reply; the reply.
;;
;; Errors: none (404, 405 or 503 replies). Side Effects: reads the
;; database; updates the metrics; logs database failures.
;; Complexity: O(1). Thread Safety: under the server's lock.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reply-status (api-handle #f "GET" "/nowhere"))
;;   404
;;   > (reply-allow (api-handle #f "POST" "/next"))
;;   "GET"
;;
;; See Also: problem.
(define (api-handle contract method path)
  (cond
    [(not (member path contract-paths))
     (problem 404 "Not Found" "the digit service has no such path")]
    [(not (string=? method "GET"))
     (problem 405 "Method Not Allowed" "only GET is allowed on this path" "GET")]
    [(string=? path "/value") (answer-digit contract 'value)]
    [(string=? path "/next") (answer-digit contract 'next)]
    [(string=? path "/health")
     (if (read-row contract)
         (reply 200 json-type "{\"status\":\"ok\",\"checks\":{\"database\":\"ok\"}}" #f)
         (reply 503 json-type "{\"status\":\"error\",\"checks\":{\"database\":\"error\"}}" #f))]
    [else (reply 200 prometheus-type (metrics-render (api-metrics contract)) #f)]))
