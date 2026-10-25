#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tests/support.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Fixtures shared by the unit tests: log capture, a
;;                  migrated in-memory database, the contract over it, a
;;                  connection fed from chunks of input and TCP clients.
;; Related Docs:    services/digit-9/README.md (Running and testing)

(require racket/runtime-path
         "../src/digit9/api.rkt"
         "../src/digit9/http.rkt"
         "../src/digit9/log.rkt"
         "../src/digit9/metrics.rkt"
         "../src/digit9/store.rkt")

(provide migrations-dir
         (struct-out capture)
         make-capture
         capture-logger
         capture-lines
         quiet-logger
         migrated
         (struct-out fixture)
         contract
         chunked-input-port
         serve-on
         serve
         statuses)

;; The migrations of the service (`migrations/`), as the image ships them.
(define-runtime-path migrations-dir "../migrations")

;; Collects the log lines of a logger instead of writing them to stdout.
;;
;; Business Justification: the tests check the log lines the service writes.
;;
;; Fields:
;;   - received: box; the captured lines, newest first.
;;   - lock: semaphore; guards `received` (the server logs from its
;;     threads).
;;
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (capture-lines (make-capture))
;;   '()
(struct capture (received lock))

;; Create an empty capture.
;;
;; Business Justification: each test starts with no captured lines.
;;
;; Parameters: none.
;;
;; Returns: capture; no lines.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (capture? (make-capture))
;;   #t
(define (make-capture)
  (capture (box '()) (make-semaphore 1)))

;; A logger of the service `digit-9` whose lines go to a capture.
;;
;; Business Justification: the code under test logs as in production, into
;; the capture.
;;
;; Parameters:
;;   - captured: capture; receives the lines.
;;   - threshold: symbol; the lowest level kept; `debug` by default.
;;
;; Returns: logger; the logger.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (logger-threshold (capture-logger (make-capture) 'info))
;;   'info
(define (capture-logger captured [threshold 'debug])
  (logger "digit-9"
          threshold
          (lambda (text)
            (call-with-semaphore (capture-lock captured)
                                 (lambda ()
                                   (set-box! (capture-received captured)
                                             (cons text (unbox (capture-received captured)))))))))

;; The captured lines, oldest first.
;;
;; Business Justification: the tests read what was logged, in order.
;;
;; Parameters:
;;   - captured: capture; the capture.
;;
;; Returns: (listof string?); the lines.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define seen (make-capture))
;;   > (log-write! (capture-logger seen) 'info "one")
;;   > (length (capture-lines seen))
;;   1
(define (capture-lines captured)
  (call-with-semaphore (capture-lock captured)
                       (lambda () (reverse (unbox (capture-received captured))))))

;; A logger that drops every line.
;;
;; Business Justification: tests that do not check the log keep the test
;; output readable.
;;
;; Parameters: none.
;;
;; Returns: logger; the logger.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (log-write! (quiet-logger) 'error "dropped")
(define (quiet-logger)
  (logger "digit-9" 'error void))

;; An in-memory database with the migrations of the service applied.
;;
;; Business Justification: the tests run against the real migrations, as the
;; service does.
;;
;; Parameters: none.
;;
;; Returns: store; the database, holding the seed of digit 9.
;;
;; Errors: raises exn:fail:store when a migration fails. Side Effects:
;; reads the migration files. Complexity: O(s). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (store-read (migrated))
;;   (digit-row 9 9 0 #t)
(define (migrated)
  (define db (open-store ":memory:" (quiet-logger)))
  (store-migrate! db migrations-dir)
  db)

;; The contract over a migrated database, with its parts.
;;
;; Business Justification: a test reaches the parts of the contract it
;; checks.
;;
;; Fields:
;;   - api: api; the contract.
;;   - store: store; its database.
;;   - metrics: metrics; its counters.
;;   - capture: capture; its log lines.
;;
;; Thread Safety: as its parts. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (store? (fixture-store (contract)))
;;   #t
(struct fixture (api store metrics capture))

;; Create the contract over a migrated in-memory database.
;;
;; Business Justification: a fresh contract per test keeps the tests
;; independent.
;;
;; Parameters:
;;   - digit: exact-integer; the configured digit; 9 by default.
;;
;; Returns: fixture; the contract and its parts.
;;
;; Errors: raises exn:fail:store when a migration fails. Side Effects:
;; reads the migration files. Complexity: O(s). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (api-digit (fixture-api (contract 5)))
;;   5
(define (contract [digit 9])
  (define db (migrated))
  (define counters (make-metrics digit "0.1.0"))
  (define captured (make-capture))
  (fixture (api db digit counters (capture-logger captured)) db counters captured))

;; An input port that delivers each chunk in reads of its own.
;;
;; Business Justification: tests input split across reads, as TCP may
;; deliver it.
;;
;; Parameters:
;;   - chunks: (listof string?); the input, ISO 8859-1 encoded; empty
;;     strings are skipped.
;;
;; Returns: input-port; a port that never returns more than the rest of
;; the current chunk in one read, then the end of the input.
;;
;; Errors: none. Side Effects: none. Complexity: O(1) per read.
;; Thread Safety: one thread. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (read-bytes-avail!* (make-bytes 10) (chunked-input-port '("ab" "cd")))
;;   2
(define (chunked-input-port chunks)
  (define remaining
    (for/list ([chunk (in-list chunks)]
               #:unless (string=? chunk ""))
      (string->bytes/latin-1 chunk)))
  (make-input-port 'chunks
                   (lambda (dest)
                     (cond
                       [(null? remaining) eof]
                       [else
                        (define chunk (car remaining))
                        (define count (min (bytes-length chunk) (bytes-length dest)))
                        (bytes-copy! dest 0 chunk 0 count)
                        (set! remaining
                              (if (= count (bytes-length chunk))
                                  (cdr remaining)
                                  (cons (subbytes chunk count) (cdr remaining))))
                        count]))
                   #f
                   void))

;; Serve an input port with a contract and return what was sent.
;;
;; Business Justification: the framing is tested without a socket.
;;
;; Parameters:
;;   - in: input-port; the client's input.
;;   - answering: api; the contract that answers.
;;   - log: logger; the logger.
;;
;; Returns: string; the output, ISO 8859-1 decoded.
;;
;; Errors: none. Side Effects: reads the port; calls the contract.
;; Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (serve-on (open-input-bytes #"") (fixture-api (contract)) (quiet-logger))
;;   ""
(define (serve-on in answering log)
  (define out (open-output-bytes))
  (serve-connection (make-input-reader in #:timeout 1)
                    out
                    (lambda (method path) (api-handle answering method path))
                    (lambda () #f)
                    log)
  (bytes->string/latin-1 (get-output-bytes out)))

;; Serve chunks of input with a fresh contract and return what was sent.
;;
;; Business Justification: the framing tests send raw requests in one call.
;;
;; Parameters:
;;   - chunks: string; the input, one chunk per argument.
;;
;; Returns: string; the output.
;;
;; Errors: raises exn:fail:store when a migration fails. Side Effects:
;; reads the migration files. Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (statuses (serve "GET /next HTTP/1.1\r\n\r\n"))
;;   '(200)
(define (serve . chunks)
  (serve-on (chunked-input-port chunks) (fixture-api (contract)) (quiet-logger)))

;; The status codes of the replies in an output, in order.
;;
;; Business Justification: the framing tests compare the replies by status.
;;
;; Parameters:
;;   - output: string; the bytes sent, decoded.
;;
;; Returns: (listof exact-integer?); the status of every status line.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (statuses "HTTP/1.1 200 OK\r\n\r\nHTTP/1.1 404 Not Found\r\n")
;;   '(200 404)
(define (statuses output)
  (for/list ([found (in-list
                     (regexp-match* #px"HTTP/1\\.1 ([0-9]{3}) " output #:match-select cadr))])
    (string->number found)))
