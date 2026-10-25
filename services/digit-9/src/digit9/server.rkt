#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/server.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Minimal HTTP/1.1 server on Racket TCP ports: one green
;;                  thread per connection, persistent connections, a
;;                  connection cap, a lingering close and a graceful stop.
;; Related Docs:    services/digit-9/README.md, contracts/http/digit.yaml,
;;                  ADR-0031

;; An accept thread starts one Racket thread per connection, each under a
;; custodian of its own that owns the connection's ports; the contract is
;; called under one lock, so the store and the metrics are never used
;; concurrently. Racket threads are scheduled by the Racket virtual machine
;; on one operating-system thread and are reclaimed by the garbage
;; collector when they end. The framing is in `http.rkt`.

(require racket/tcp
         "api.rkt"
         "http.rkt"
         "log.rkt")

(provide max-connections
         (struct-out exn:fail:server)
         (struct-out digit-server)
         start-server
         server-stop!)

;; Most connections served at once; further ones are closed on accept.
(define max-connections 256)

;; Length of the queue of connections the kernel accepts before the server
;; does.
(define listen-backlog 256)

;; Milliseconds the server waits for running requests after a stop.
(define drain-timeout-ms 5000)

;; Milliseconds unread input is still read and discarded after the last
;; reply, before the connection is closed.
(define linger-ms 200)

;; Most bytes discarded after the last reply; a client still sending more
;; is cut off.
(define linger-bytes 16384)

;; Milliseconds the accept thread waits after a failed accept (for example
;; too many open files) before it accepts again.
(define accept-retry-ms 200)

;; A failure to start the server (the port cannot be bound).
;;
;; Fields: those of exn:fail (message and continuation marks); the message
;; is the system's.
;;
;; Business Justification: a port in use stops the start with a clear log
;; line instead of a stack trace.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (exn-message (exn:fail:server "Address in use" (current-continuation-marks)))
;;   "Address in use"
(struct exn:fail:server exn:fail ())

;; The HTTP server of the digit service.
;;
;; Description: an accept thread starts one thread per connection; the
;; contract is called under `api-lock`. All the threads belong to the
;; server's custodians, and the process ends when `run` returns, whatever
;; they do.
;;
;; Fields:
;;   - listener: tcp-listener; the listening socket.
;;   - port: exact-integer; the bound port.
;;   - contract: api; the contract that answers each request.
;;   - log: logger; the logger.
;;   - api-lock: semaphore; serialises the calls to the contract.
;;   - state-lock: semaphore; guards `connections` and `stopping?`.
;;   - connections: (hash/c custodian? #t); the open connections, keyed by
;;     the custodian that owns their thread and ports (mutable hash).
;;   - stop-signal: semaphore; posted once by `server-stop!`; its peek
;;     event wakes the accept thread and the idle connections.
;;   - stopping?: boolean; #t once the server stops (mutable).
;;   - accept-thread: (or/c thread? #f); the accept thread (mutable).
;;
;; Business Justification: the transport of the digit contract on port
;; 8080 (CLAUDE.md 6.1).
;;
;; Thread Safety: safe; the shared state is guarded by `state-lock` and the
;; contract by `api-lock` (ADR-0031).
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (digit-server-port (start-server 0 contract log)) ; a free port
(struct digit-server
        (listener port
                  contract
                  log
                  api-lock
                  state-lock
                  connections
                  stop-signal
                  [stopping? #:mutable]
                  [accept-thread #:mutable]))

;; Bind a port on all IPv4 addresses and start serving.
;;
;; Description: the bind happens here, so a port in use fails the start.
;; Above `max-connections` a new connection is closed at once.
;;
;; Business Justification: port 8080 of every service (CLAUDE.md 6.1).
;;
;; Parameters:
;;   - port: exact-integer; the TCP port, 1..65535 (0 picks a free port,
;;     for the tests).
;;   - contract: api; the contract that answers each request.
;;   - log: logger; the logger.
;;
;; Returns: digit-server; the running server.
;;
;; Errors: raises exn:fail:server when the socket cannot be bound.
;; Side Effects: opens a socket; starts the accept thread.
;; Complexity: O(1). Thread Safety: call once per port.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (define server (start-server 8080 contract log))
;;
;; See Also: server-stop!.
(define (start-server port contract log)
  (define listener
    (with-handlers ([exn:fail:network? (lambda (error) (server-fail (exn-message error)))])
      (tcp-listen port listen-backlog #t "0.0.0.0")))
  (define-values (_address bound _peer _peer-port) (tcp-addresses listener #t))
  (define server
    (digit-server listener
                  bound
                  contract
                  log
                  (make-semaphore 1)
                  (make-semaphore 1)
                  (make-hasheq)
                  (make-semaphore 0)
                  #f
                  #f))
  (set-digit-server-accept-thread! server (thread (lambda () (accept-loop server))))
  server)

;; Raise a start failure with a one-line message.
;;
;; Parameters:
;;   - message: string; the system message; its line breaks become `; `.
;;
;; Returns: never returns.
;;
;; Errors: always raises exn:fail:server. Side Effects: none.
;; Complexity: O(n). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (with-handlers ([exn:fail:server? exn-message])
;;       (server-fail "listen failed\n  port number: 8080"))
;;   "listen failed; port number: 8080"
(define (server-fail message)
  (raise (exn:fail:server (regexp-replace* #rx"\n *" message "; ") (current-continuation-marks))))

;; Whether the server stops.
;;
;; Parameters:
;;   - server: digit-server; the server.
;;
;; Returns: boolean; the flag, read under the state lock.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (server-stopping? server) ; #f until server-stop!
(define (server-stopping? server)
  (call-with-semaphore (digit-server-state-lock server)
                       (lambda () (digit-server-stopping? server))))

;; Accept connections until the server stops.
;;
;; Description: each accepted connection gets a custodian and a thread of
;; its own; above `max-connections` it is closed at once. A failed accept
;; is logged and retried after `accept-retry-ms`.
;;
;; Parameters:
;;   - server: digit-server; the server.
;;
;; Returns: void, once the server stops.
;;
;; Errors: none. Side Effects: accepts connections; starts threads; logs.
;; Complexity: O(1) per connection. Thread Safety: the accept thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (thread (lambda () (accept-loop server)))
(define (accept-loop server)
  (define stop-evt (semaphore-peek-evt (digit-server-stop-signal server)))
  (let loop ()
    (define custodian (make-custodian))
    (define accepted
      (with-handlers ([exn:fail:network? (lambda (error) error)])
        (parameterize ([current-custodian custodian])
          (sync (tcp-accept-evt (digit-server-listener server)) stop-evt))))
    (cond
      [(or (eq? accepted stop-evt) (server-stopping? server)) (custodian-shutdown-all custodian)]
      [(exn? accepted)
       (custodian-shutdown-all custodian)
       (log-write! (digit-server-log server) 'warn "accept failed" (exn-message accepted))
       (sleep (/ accept-retry-ms 1000))
       (loop)]
      [(admit! server custodian)
       (define in (car accepted))
       (define out (cadr accepted))
       (parameterize ([current-custodian custodian])
         (thread (lambda () (serve! server custodian in out))))
       (loop)]
      [else
       (custodian-shutdown-all custodian)
       (log-write! (digit-server-log server)
                   'warn
                   "connection limit reached; connection closed"
                   (number->string max-connections))
       (loop)])))

;; Record a connection unless the server is at its connection limit.
;;
;; Parameters:
;;   - server: digit-server; the server.
;;   - custodian: custodian; the custodian of the connection.
;;
;; Returns: boolean; #t when the connection was recorded.
;;
;; Errors: none. Side Effects: updates the state. Complexity: O(1).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (admit! server (make-custodian)) ; #t below 256 connections
(define (admit! server custodian)
  (define connections (digit-server-connections server))
  (call-with-semaphore (digit-server-state-lock server)
                       (lambda ()
                         (and (< (hash-count connections) max-connections)
                              (begin
                                (hash-set! connections custodian #t)
                                #t)))))

;; Remove a connection from the open connections.
;;
;; Parameters:
;;   - server: digit-server; the server.
;;   - custodian: custodian; the custodian of the connection.
;;
;; Returns: void.
;;
;; Errors: none. Side Effects: updates the state. Complexity: O(1).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (forget! server custodian)
(define (forget! server custodian)
  (call-with-semaphore (digit-server-state-lock server)
                       (lambda () (hash-remove! (digit-server-connections server) custodian))))

;; Serve one connection on its own thread, then close it.
;;
;; Description: the reader's wake event is the server's stop, so an idle
;; connection ends when the server stops. At the end the connection is
;; forgotten, closed with a linger, and its custodian shut down, which
;; ends this thread.
;;
;; Parameters:
;;   - server: digit-server; the server.
;;   - custodian: custodian; the custodian of the connection and of this
;;     thread.
;;   - in: input-port; the connection's input.
;;   - out: output-port; the connection's output.
;;
;; Returns: never returns normally: the last step shuts down the
;; custodian of the calling thread.
;;
;; Errors: none (a failure is logged). Side Effects: reads and writes the
;; connection; calls the contract under the lock; updates the state.
;; Complexity: that of the requests. Thread Safety: one thread per
;; connection. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (thread (lambda () (serve! server custodian in out)))
(define (serve! server custodian in out)
  (define log (digit-server-log server))
  (define reader
    (make-input-reader in #:wake (semaphore-peek-evt (digit-server-stop-signal server))))
  (with-handlers ([exn:fail? (lambda (error)
                               (log-write! log 'error "connection failed" (exn-message error)))])
    (serve-connection
     reader
     out
     (lambda (method path)
       (call-with-semaphore (digit-server-api-lock server)
                            (lambda () (api-handle (digit-server-contract server) method path))))
     (lambda () (server-stopping? server))
     log))
  (forget! server custodian)
  (linger-close! in out)
  (custodian-shutdown-all custodian))

;; Close a connection with a linger: stop writing, discard input for up to
;; `linger-ms` or `linger-bytes`, then close the input.
;;
;; Business Justification: closing a socket with unread input makes the
;; kernel send a reset that can destroy the last reply (ADR-0026).
;;
;; Parameters:
;;   - in: input-port; the connection's input.
;;   - out: output-port; the connection's output.
;;
;; Returns: void.
;;
;; Errors: none (failures of a reset connection are ignored).
;; Side Effects: closes the connection. Complexity: O(n) in the discarded
;; bytes. Thread Safety: one thread. Owner: Arithmetic Excellence Center
;; (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (linger-close! (open-input-bytes #"unread") (open-output-bytes))
(define (linger-close! in out)
  (with-handlers ([exn:fail? void])
    (close-output-port out))
  (define deadline (+ (current-inexact-milliseconds) linger-ms))
  (define chunk (make-bytes 4096))
  (let discard ([discarded 0])
    (define remaining (- deadline (current-inexact-milliseconds)))
    (when (and (<= discarded linger-bytes) (positive? remaining))
      (define count
        (with-handlers ([exn:fail? (lambda (_) eof)])
          (and (sync/timeout (/ remaining 1000) in) (read-bytes-avail!* chunk in))))
      (when (exact-nonnegative-integer? count)
        (discard (+ discarded count)))))
  (with-handlers ([exn:fail? void])
    (close-input-port in)))

;; Whether every connection is closed and the accept thread ended.
;;
;; Parameters:
;;   - server: digit-server; the server.
;;
;; Returns: boolean; #t when nothing is left to wait for.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (drained? server) ; #t after a completed stop
(define (drained? server)
  (and (thread-dead? (digit-server-accept-thread server))
       (call-with-semaphore (digit-server-state-lock server)
                            (lambda () (zero? (hash-count (digit-server-connections server)))))))

;; Stop the server.
;;
;; Description: stops accepting, wakes the idle connections, which close,
;; and waits up to `drain-timeout-ms` for running requests, which are
;; answered with Connection: close; then shuts down what is left.
;;
;; Business Justification: graceful shutdown in at most 10 s
;; (CLAUDE.md 6.1).
;;
;; Parameters:
;;   - server: digit-server; the server.
;;
;; Returns: void.
;;
;; Errors: none. Side Effects: closes the listener and the connections.
;; Complexity: O(c) in the open connections. Thread Safety: call once.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (server-stop! server)
;;
;; See Also: start-server.
(define (server-stop! server)
  (call-with-semaphore (digit-server-state-lock server)
                       (lambda () (set-digit-server-stopping?! server #t)))
  (semaphore-post (digit-server-stop-signal server))
  (thread-wait (digit-server-accept-thread server))
  (tcp-close (digit-server-listener server))
  (let wait ([waited 0])
    (unless (or (drained? server) (>= waited drain-timeout-ms))
      (sleep 0.02)
      (wait (+ waited 20))))
  (for ([custodian (in-list (call-with-semaphore
                             (digit-server-state-lock server)
                             (lambda () (hash-keys (digit-server-connections server)))))])
    (custodian-shutdown-all custodian)))
