#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tests/contract-test.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Unit tests of the contract and the database: the
;;                  migrations, the seed of digit 9, the replies of every
;;                  path and the database failures.
;; Related Docs:    contracts/http/digit.yaml, migrations/0001_digit.sql

(require racket/file
         racket/string
         rackunit
         "../src/digit9/api.rkt"
         "../src/digit9/metrics.rkt"
         "../src/digit9/store.rkt"
         "support.rkt")

;; The message of the store failure a thunk raises.
;;
;; Parameters:
;;   - thunk: (-> any); the code expected to fail.
;;
;; Returns: (or/c string? #f); the message, or #f when nothing was raised.
;;
;; Errors: re-raises anything other than exn:fail:store. Side Effects:
;; those of `thunk`. Complexity: that of `thunk`. Thread Safety: one test.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (store-failure (lambda () (store-read (open-store ":memory:" (quiet-logger)))))
;;   "no such table: digit"
(define (store-failure thunk)
  (with-handlers ([exn:fail:store? exn-message])
    (thunk)
    #f))

(test-case "the migrations apply once: a second run applies nothing"
  (define db (open-store ":memory:" (quiet-logger)))
  (check-equal? (store-migrate! db migrations-dir) 1)
  (check-equal? (store-migrate! db migrations-dir) 0)
  (check-true (store-applied? db "0001_digit.sql"))
  (check-false (store-applied? db "0002_missing.sql")))

(test-case "the seed holds digit 9: value 9, successor 0, carry"
  (check-equal? (store-read (migrated)) (digit-row 9 9 0 #t)))

(test-case "a missing migrations directory fails with its path"
  (check-equal? (store-failure (lambda ()
                                 (store-migrate! (open-store ":memory:" (quiet-logger))
                                                 "/nonexistent/migrations")))
                "cannot read the migrations directory /nonexistent/migrations"))

(test-case "a failing migration is rolled back and not recorded; the earlier one stays"
  (define dir (make-temporary-directory))
  (dynamic-wind void
                (lambda ()
                  (display-to-file "CREATE TABLE a (x INTEGER) STRICT;"
                                   (build-path dir "0001_a.sql"))
                  (display-to-file "CREATE TABLE b (x INTEGER); INSERT INTO nowhere VALUES (1);"
                                   (build-path dir "0002_b.sql"))
                  (display-to-file "garbage" (build-path dir ".0003_hidden.sql"))
                  (display-to-file "garbage" (build-path dir "notes.txt"))
                  (define db (open-store ":memory:" (quiet-logger)))
                  (define message (store-failure (lambda () (store-migrate! db dir))))
                  (check-equal? message "migration 0002_b.sql failed: no such table: nowhere")
                  (check-true (store-applied? db "0001_a.sql"))
                  (check-false (store-applied? db "0002_b.sql"))
                  (store-execute! db "INSERT INTO a VALUES (1);")
                  (check-equal? (store-failure (lambda () (store-execute! db "SELECT * FROM b;")))
                                "no such table: b"))
                (lambda () (delete-directory/files dir))))

(test-case "the digit table must hold exactly one row"
  (define db (migrated))
  (store-execute! db "INSERT INTO digit VALUES (8, 8, 9, 0);")
  (check-equal? (store-failure (lambda () (store-read db)))
                "the table digit holds more than one row")
  (store-execute! db "DELETE FROM digit;")
  (check-equal? (store-failure (lambda () (store-read db))) "the table digit holds no row"))

(test-case "a database that cannot be opened fails with the SQLite message"
  (check-equal? (store-failure (lambda () (open-store "/nonexistent/dir/d.db" (quiet-logger))))
                "cannot open the database: unable to open database file"))

(test-case "a closed store fails instead of using a released connection"
  (define db (migrated))
  (store-close! db)
  (store-close! db)
  (check-equal? (store-failure (lambda () (store-read db))) "the database is closed"))

(test-case "GET /value and GET /next answer the seeded row as JSON"
  (define contract-api (fixture-api (contract)))
  (define value (api-handle contract-api "GET" "/value"))
  (check-equal? (reply-status value) 200)
  (check-equal? (reply-content-type value) json-type)
  (check-equal? (reply-body value) "{\"digit\":9,\"value\":9}")
  (define next (api-handle contract-api "GET" "/next"))
  (check-equal? (reply-status next) 200)
  (check-equal? (reply-body next) "{\"digit\":9,\"next\":0,\"carry\":true}"))

(test-case "the replies come from the database on every request, not from code"
  (define parts (contract))
  (store-execute! (fixture-store parts) "UPDATE digit SET next = 7, carry = 0;")
  (check-equal? (reply-body (api-handle (fixture-api parts) "GET" "/next"))
                "{\"digit\":9,\"next\":7,\"carry\":false}"))

(test-case "GET /health reports the database check"
  (define parts (contract))
  (define healthy (api-handle (fixture-api parts) "GET" "/health"))
  (check-equal? (reply-status healthy) 200)
  (check-equal? (reply-content-type healthy) json-type)
  (check-equal? (reply-body healthy) "{\"status\":\"ok\",\"checks\":{\"database\":\"ok\"}}")
  (store-execute! (fixture-store parts) "DROP TABLE digit;")
  (define unhealthy (api-handle (fixture-api parts) "GET" "/health"))
  (check-equal? (reply-status unhealthy) 503)
  (check-equal? (reply-body unhealthy)
                "{\"status\":\"error\",\"checks\":{\"database\":\"error\"}}"))

(test-case "a database failure answers 503 problem details, counts an error and logs it"
  (define parts (contract))
  (store-execute! (fixture-store parts) "DROP TABLE digit;")
  (define answer (api-handle (fixture-api parts) "GET" "/value"))
  (check-equal? (reply-status answer) 503)
  (check-equal? (reply-content-type answer) problem-type)
  (check-true (string-contains? (reply-body answer)
                                "\"title\":\"Service Unavailable\",\"status\":503"))
  (check-equal? (metrics-get (fixture-metrics parts) 'value 'error) 1)
  (check-equal? (metrics-get (fixture-metrics parts) 'value 'ok) 0)
  (define lines (capture-lines (fixture-capture parts)))
  (check-equal? (length lines) 1)
  (check-true (string-contains? (car lines) "\"level\":\"error\""))
  (check-true (string-contains? (car lines) "\"detail\":\"no such table: digit\"")))

(test-case "a database holding another digit is refused"
  (define parts (contract 5))
  (check-equal? (reply-status (api-handle (fixture-api parts) "GET" "/next")) 503)
  (check-equal? (reply-status (api-handle (fixture-api parts) "GET" "/health")) 503)
  (check-true (string-contains? (car (capture-lines (fixture-capture parts)))
                                "the database holds another digit")))

(test-case "unknown paths answer 404, other methods 405 with Allow: GET"
  (define contract-api (fixture-api (contract)))
  (define missing (api-handle contract-api "GET" "/"))
  (check-equal? (reply-status missing) 404)
  (check-equal? (reply-content-type missing) problem-type)
  (check-false (reply-allow missing))
  (check-equal? (reply-status (api-handle contract-api "POST" "/nope")) 404)
  (for ([path (in-list '("/value" "/next" "/health" "/metrics"))])
    (define answer (api-handle contract-api "POST" path))
    (check-equal? (reply-status answer) 405)
    (check-equal? (reply-allow answer) "GET"))
  (check-equal? (reply-status (api-handle contract-api "get" "/value")) 405))

(test-case "GET /metrics exposes the counters of the answered requests"
  (define contract-api (fixture-api (contract)))
  (for ([path (in-list '("/value" "/next" "/next" "/health"))])
    (api-handle contract-api "GET" path))
  (define answer (api-handle contract-api "GET" "/metrics"))
  (check-equal? (reply-status answer) 200)
  (check-equal? (reply-content-type answer) prometheus-type)
  (define body (reply-body answer))
  (check-true
   (string-contains? body "digit_requests_total{digit=\"9\",endpoint=\"value\",outcome=\"ok\"} 1"))
  (check-true
   (string-contains? body "digit_requests_total{digit=\"9\",endpoint=\"next\",outcome=\"ok\"} 2"))
  (check-true (string-contains?
               body
               "digit_requests_total{digit=\"9\",endpoint=\"next\",outcome=\"error\"} 0"))
  (check-true (string-contains? body "# TYPE digit_build_info gauge")))
