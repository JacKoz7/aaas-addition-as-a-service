#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tests/server-test.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Unit tests of the server over TCP on a free port:
;;                  keep-alive, the graceful stop, the connection limit,
;;                  the bookkeeping of ended connections, a port in use and
;;                  the configuration and start-up checks.
;; Related Docs:    src/digit9/server.rkt, src/digit9/service.rkt

(require racket/list
         racket/string
         racket/tcp
         rackunit
         "../src/digit9/server.rkt"
         "../src/digit9/service.rkt"
         "support.rkt")

;; Seconds a test waits for the server before it fails.
(define patience-seconds 5)

;; Start a server on a free port over a fresh contract.
;;
;; Parameters:
;;   - captured: capture; receives the server's log lines.
;;
;; Returns: digit-server; the running server.
;;
;; Errors: raises exn:fail:server when no port can be bound. Side Effects:
;; opens a socket; starts threads. Complexity: O(1). Thread Safety: one
;; test. Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (start (make-capture))
(define (start captured)
  (start-server 0 (fixture-api (contract)) (capture-logger captured)))

;; Open a client connection to a server.
;;
;; Parameters:
;;   - server: digit-server; the running server.
;;
;; Returns: (cons/c input-port? output-port?); the client's ports.
;;
;; Errors: raises exn:fail:network when the connection fails.
;; Side Effects: one connection. Complexity: O(1). Thread Safety: one test.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (connect server)
(define (connect server)
  (define-values (in out) (tcp-connect "127.0.0.1" (digit-server-port server)))
  (cons in out))

;; Send text on a client connection.
;;
;; Parameters:
;;   - client: (cons/c input-port? output-port?); the client.
;;   - text: string; the bytes to send, ISO 8859-1 encoded.
;;
;; Returns: void.
;;
;; Errors: raises exn:fail:network when the connection is closed.
;; Side Effects: writes the socket. Complexity: O(n). Thread Safety: one
;; test. Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (send! client "GET /value HTTP/1.1\r\n\r\n")
(define (send! client text)
  (write-bytes (string->bytes/latin-1 text) (cdr client))
  (flush-output (cdr client)))

;; Read from a client connection until a text has arrived, the input ends
;; or `patience-seconds` pass.
;;
;; Parameters:
;;   - client: (cons/c input-port? output-port?); the client.
;;   - until: (or/c string? #f); the text to wait for, or #f to read to the
;;     end of the input.
;;
;; Returns: string; everything read, ISO 8859-1 decoded.
;;
;; Errors: none (a reset ends the read). Side Effects: reads the socket.
;; Complexity: O(n). Thread Safety: one test.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (receive client "}")
(define (receive client until)
  (define in (car client))
  (define deadline (+ (current-inexact-milliseconds) (* 1000 patience-seconds)))
  (let loop ([text ""])
    (define remaining (/ (- deadline (current-inexact-milliseconds)) 1000))
    (cond
      [(and until (string-contains? text until)) text]
      [(<= remaining 0) text]
      [else
       (define buffer (make-bytes 4096))
       (define count
         (with-handlers ([exn:fail? (lambda (_) eof)])
           (and (sync/timeout remaining in) (read-bytes-avail!* buffer in))))
       (cond
         [(exact-nonnegative-integer? count)
          (loop (string-append text (bytes->string/latin-1 (subbytes buffer 0 count))))]
         [else text])])))

;; Close a client connection.
;;
;; Parameters:
;;   - client: (cons/c input-port? output-port?); the client.
;;
;; Returns: void.
;;
;; Errors: none. Side Effects: closes the socket. Complexity: O(1).
;; Thread Safety: one test. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (disconnect! client)
(define (disconnect! client)
  (close-output-port (cdr client))
  (close-input-port (car client)))

;; Wait until a condition holds or `patience-seconds` pass.
;;
;; Parameters:
;;   - ready?: (-> boolean?); the condition.
;;
;; Returns: boolean; the last value of the condition.
;;
;; Errors: none. Side Effects: sleeps. Complexity: O(t). Thread Safety:
;; one test. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (eventually (lambda () #t))
;;   #t
(define (eventually ready?)
  (let loop ([waited 0])
    (cond
      [(ready?) #t]
      [(>= waited (* 1000 patience-seconds)) #f]
      [else
       (sleep 0.02)
       (loop (+ waited 20))])))

(test-case "requests over TCP on one keep-alive connection, then a stop that closes it at once"
  (define server (start (make-capture)))
  (define client (connect server))
  (send! client "GET /value HTTP/1.1\r\nHost: x\r\n\r\n")
  (check-true (string-contains? (receive client "{\"digit\":9,\"value\":9}") "HTTP/1.1 200 OK"))
  (send! client "GET /next HTTP/1.1\r\nHost: x\r\n\r\n")
  (check-true (string-suffix? (receive client "}") "{\"digit\":9,\"next\":0,\"carry\":true}"))
  (define started (current-inexact-milliseconds))
  (server-stop! server)
  (check-true (< (- (current-inexact-milliseconds) started) 1000))
  (check-equal? (receive client #f) "")
  (disconnect! client))

(test-case "a request running during the stop is answered with Connection: close"
  (define server (start (make-capture)))
  (define client (connect server))
  (send! client "GET /value HTTP/1.1\r\nContent-Length: 5\r\n\r\nab")
  (sleep 0.1)
  (define stopper (thread (lambda () (server-stop! server))))
  (sleep 0.1)
  (send! client "cde")
  (define answer (receive client #f))
  (thread-wait stopper)
  (check-true (string-contains? answer "HTTP/1.1 200 OK"))
  (check-true (string-contains? answer "Connection: close"))
  (disconnect! client))

(test-case "above the connection limit, new connections are closed at once and logged"
  (define captured (make-capture))
  (define server (start captured))
  (define clients
    (for/list ([_ (in-range max-connections)])
      (connect server)))
  (check-true (eventually (lambda ()
                            (= (hash-count (digit-server-connections server)) max-connections))))
  (define extra (connect server))
  (check-equal? (receive extra #f) "")
  (send! (last clients) "GET /health HTTP/1.1\r\n\r\n")
  (check-true (string-contains? (receive (last clients) "}") "HTTP/1.1 200 OK"))
  (check-true (for/or ([text (in-list (capture-lines captured))])
                (string-contains? text "connection limit reached")))
  (for-each disconnect! clients)
  (disconnect! extra)
  (server-stop! server))

(test-case "ended connections are forgotten: 100 closing calls leave no connection behind"
  (define server (start (make-capture)))
  (for ([_ (in-range 100)])
    (define client (connect server))
    (send! client "GET /value HTTP/1.1\r\nConnection: close\r\n\r\n")
    (check-true (string-contains? (receive client #f) "Connection: close"))
    (disconnect! client))
  (check-true (eventually (lambda () (zero? (hash-count (digit-server-connections server))))))
  (server-stop! server))

(test-case "a client that resets mid-request does not disturb the server"
  (define server (start (make-capture)))
  (for ([_ (in-range 20)])
    (define client (connect server))
    (send! client "GET /val")
    (tcp-abandon-port (cdr client))
    (close-input-port (car client)))
  (define client (connect server))
  (send! client "GET /health HTTP/1.1\r\n\r\n")
  (check-true (string-contains? (receive client "}") "HTTP/1.1 200 OK"))
  (disconnect! client)
  (server-stop! server))

(test-case "a port in use fails the start with the system message"
  (define captured (make-capture))
  (define first-server (start captured))
  (check-exn exn:fail:server?
             (lambda ()
               (start-server (digit-server-port first-server)
                             (fixture-api (contract))
                             (capture-logger captured))))
  (server-stop! first-server))

;; The variables the configuration test sets, cleared after it.
(define configuration-variables
  '("AAAS_BOOTSTRAP" "AAAS_DIGIT"
                     "AAAS_HTTP_PORT"
                     "AAAS_DB_PATH"
                     "AAAS_MIGRATIONS_DIR"
                     "AAAS_LOG_LEVEL"))

;; Set an environment variable, or remove it.
;;
;; Parameters:
;;   - name: string; the variable.
;;   - value: (or/c string? #f); the value, or #f to remove it.
;;
;; Returns: void.
;;
;; Errors: none. Side Effects: changes the environment of the process.
;; Complexity: O(1). Thread Safety: one test.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (set-variable! "AAAS_UNIT_TEST_VARIABLE" #f)
(define (set-variable! name value)
  (void (environment-variables-set! (current-environment-variables)
                                    (string->bytes/utf-8 name)
                                    (and value (string->bytes/utf-8 value)))))

;; Run the service on a thread of its own and return its exit status.
;;
;; Description: `run` disables breaks in its thread; a thread of its own
;; keeps the test thread unchanged.
;;
;; Parameters: none.
;;
;; Returns: exact-integer; the status `run` returned.
;;
;; Errors: none. Side Effects: those of `run`. Complexity: that of the
;; start. Thread Safety: one test. Owner: Arithmetic Excellence Center
;; (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (run-status) ; 1 when a start-up check fails
(define (run-status)
  (define status #f)
  (thread-wait (thread (lambda () (set! status (run)))))
  status)

(test-case "the configuration accepts the defaults and refuses invalid values; run stops with 1"
  (dynamic-wind
   void
   (lambda ()
     (define captured (make-capture))
     (check-equal? (load-config (capture-logger captured))
                   (config 9 8080 "/data/digit-9.db" "/app/migrations"))
     (for ([setting (in-list '(("AAAS_BOOTSTRAP" "platform") ("AAAS_DIGIT" "x")
                                                             ("AAAS_DIGIT" "10")
                                                             ("AAAS_HTTP_PORT" "0")
                                                             ("AAAS_HTTP_PORT" "65536")))])
       (set-variable! (first setting) (second setting))
       (check-false (load-config (capture-logger captured)) (string-join setting "="))
       (set-variable! (first setting) #f))
     (set-variable! "AAAS_LOG_LEVEL" "error")
     (set-variable! "AAAS_DB_PATH" ":memory:")
     (set-variable! "AAAS_MIGRATIONS_DIR" "/nonexistent/migrations")
     (define output (open-output-string))
     (parameterize ([current-output-port output])
       (check-equal? (run-status) 1)
       (set-variable! "AAAS_MIGRATIONS_DIR" (path->string migrations-dir))
       (set-variable! "AAAS_DIGIT" "5")
       (check-equal? (run-status) 1))
     (define lines (string-split (get-output-string output) "\n"))
     (check-equal? (length lines) 2)
     (check-true (string-contains? (first lines) "the database cannot be prepared"))
     (check-true (string-contains? (second lines)
                                   "the database does not hold the configured digit")))
   (lambda () (for-each (lambda (name) (set-variable! name #f)) configuration-variables))))
