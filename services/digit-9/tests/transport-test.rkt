#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tests/transport-test.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Unit tests of the HTTP/1.1 framing over string ports:
;;                  persistent connections, pipelining, split input, bodies,
;;                  limits, malformed requests, trace context and log lines.
;; Related Docs:    src/digit9/http.rkt, RFC 9112

(require json
         racket/list
         racket/string
         rackunit
         "../src/digit9/http.rkt"
         "../src/digit9/log.rkt"
         "../src/digit9/trace.rkt"
         "support.rkt")

(test-case "two requests on one HTTP/1.1 connection are both answered; it stays open"
  (define output
    (serve "GET /value HTTP/1.1\r\nHost: x\r\n\r\n" "GET /next HTTP/1.1\r\nHost: x\r\n\r\n"))
  (check-equal? (statuses output) '(200 200))
  (check-false (string-contains? output "Connection: close"))
  (check-true (string-suffix? output "{\"digit\":9,\"next\":0,\"carry\":true}")))

(test-case "pipelined requests in one chunk are answered in order"
  (check-equal? (statuses (serve (string-append "GET /value HTTP/1.1\r\n\r\n"
                                                "GET /nope HTTP/1.1\r\n\r\n"
                                                "GET /next HTTP/1.1\r\n\r\n")))
                '(200 404 200)))

(test-case "input split into single bytes is reassembled"
  (define request "GET /value?probe=1 HTTP/1.1\r\nHost: x\r\n\r\n")
  (define output
    (apply serve
           (for/list ([c (in-string request)])
             (string c))))
  (check-equal? (statuses output) '(200))
  (check-true (string-suffix? output "{\"digit\":9,\"value\":9}")))

(test-case "empty lines before the request line are skipped; bare LF endings are accepted"
  (check-equal? (statuses (serve "\r\n\nGET /health HTTP/1.1\nHost: x\n\n")) '(200)))

(test-case "HTTP/1.0 closes after the reply unless it asks for keep-alive"
  (define closed (serve "GET /value HTTP/1.0\r\n\r\nGET /value HTTP/1.0\r\n\r\n"))
  (check-equal? (statuses closed) '(200))
  (check-true (string-contains? closed "Connection: close"))
  (check-equal?
   (statuses
    (serve "GET /value HTTP/1.0\r\nConnection: keep-alive\r\n\r\nGET /next HTTP/1.0\r\n\r\n"))
   '(200 200)))

(test-case "Connection: close on HTTP/1.1 ends the connection after the reply"
  (define output
    (serve
     "GET /value HTTP/1.1\r\nConnection: Keep-Alive, close\r\n\r\nGET /next HTTP/1.1\r\n\r\n"))
  (check-equal? (statuses output) '(200))
  (check-true (string-contains? output "Connection: close")))

(test-case "HEAD gets the headers of the 405 without its body"
  (define output (serve "HEAD /value HTTP/1.1\r\n\r\nGET /value HTTP/1.1\r\n\r\n"))
  (check-equal? (statuses output) '(405 200))
  (check-true (string-contains? output "Allow: GET\r\n\r\nHTTP/1.1 200")))

(test-case "a Content-Length body is read and skipped, not taken for a request"
  (check-equal? (statuses (serve "POST /value HTTP/1.1\r\nContent-Length: 10\r\n\r\n"
                                 "0123456789"
                                 "GET /next HTTP/1.1\r\n\r\n"))
                '(405 200)))

(test-case "a chunked body with a trailer field is skipped"
  (check-equal? (statuses (serve (string-append
                                  "POST /next HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
                                  "5;ext=1\r\nhello\r\na\r\n0123456789\r\n0\r\nX-Trailer: 1\r\n\r\n"
                                  "GET /next HTTP/1.1\r\n\r\n")))
                '(405 200)))

(test-case "bodies above the limit answer 413 and close, whichever framing"
  (define by-length
    (serve (format "POST /value HTTP/1.1\r\nContent-Length: ~a\r\n\r\n" (add1 max-body))))
  (check-equal? (statuses by-length) '(413))
  (check-true (string-contains? by-length "Connection: close"))
  (check-equal? (statuses (serve (format "POST /value HTTP/1.1\r\nContent-Length: ~a\r\n\r\n"
                                         max-body)
                                 (make-string max-body #\x)
                                 "GET /value HTTP/1.1\r\n\r\n"))
                '(405 200))
  (check-equal?
   (statuses (serve "POST /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n10001\r\n"))
   '(413)))

(test-case "ambiguous or invalid framing answers 400 and closes"
  (for ([request
         (in-list
          '("POST /value HTTP/1.1\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n"
            "POST /value HTTP/1.1\r\nTransfer-Encoding: gzip\r\n\r\n"
            "POST /value HTTP/1.1\r\nContent-Length: -1\r\n\r\n"
            "POST /value HTTP/1.1\r\nContent-Length: 1, 1\r\n\r\n"
            "POST /value HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\n"
            "POST /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\n"
            "POST /value HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabcX\r\n"))])
    (define output (serve request))
    (check-equal? (statuses output) '(400) request)
    (check-true (string-contains? output "Connection: close") request)))

(test-case "a truncated body answers 400"
  (check-equal? (statuses (serve "POST /value HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc")) '(400)))

(test-case "malformed heads answer 400 problem details"
  (for ([request (in-list '("garbage\r\n\r\n" "GET /value HTTP/2.0\r\n\r\n"
                                              "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
                                              "GET  /value HTTP/1.1\r\n\r\n"
                                              "G(T /value HTTP/1.1\r\n\r\n"
                                              "GET /value HTTP/1.1\r\nno colon\r\n\r\n"
                                              "GET /value HTTP/1.1\r\n folded: x\r\n\r\n"
                                              "GET /value HTTP/1.1\r\nHost: x\r\n"))])
    (define output (serve request))
    (check-equal? (statuses output) '(400) request)
    (check-true (string-contains? output "application/problem+json") request)))

(test-case "heads above 8 KiB answer 431, whether one line or many is too long"
  (check-equal?
   (statuses (serve (string-append "GET /" (make-string max-head #\a) " HTTP/1.1\r\n\r\n")))
   '(431))
  (define many
    (string-append* "GET /value HTTP/1.1\r\n"
                    (for/list ([i (in-range 200)])
                      (format "X-Header-~a: ~a\r\n" i (make-string 40 #\v)))))
  (check-equal? (statuses (serve (string-append many "\r\n"))) '(431))
  (check-equal? (statuses (serve (string-append "GET /value HTTP/1.1\r\nX: "
                                                (make-string max-head #\v))))
                '(431)))

(test-case "a head just under the limit is answered"
  (define head "GET /value HTTP/1.1\r\nX: ")
  (define filler (make-string (- max-head (string-length head) 4) #\v))
  (check-equal? (statuses (serve (string-append head filler "\r\n\r\n"))) '(200))
  (check-equal? (statuses (serve (string-append head filler "v\r\n\r\n"))) '(431)))

(test-case "an input that ends before a request line is a clean end: no reply"
  (check-equal? (serve) "")
  (check-equal? (serve "GET /val") "")
  (check-equal? (serve "\r\n") ""))

(test-case "a silent connection ends after the receive timeout without a reply"
  (define-values (in out) (make-pipe))
  (write-string "GET /val" out)
  (define started (current-inexact-milliseconds))
  (define reader (make-input-reader in #:timeout 0.2))
  (check-equal? (head-result-ended? (read-head reader)) #t)
  (check-true (< (- (current-inexact-milliseconds) started) 2000)))

(test-case "the wake event ends a reader that waits for input"
  (define in (make-input-port 'silent (lambda (_) never-evt) #f void))
  (define wake (make-semaphore 0))
  (define reader (make-input-reader in #:wake (semaphore-peek-evt wake)))
  (semaphore-post wake)
  (check-equal? (line-status (reader-read-line reader 100)) 'closed))

(test-case "the reply has the headers of the contract and a JSON body"
  (define output (serve "GET /value HTTP/1.1\r\n\r\n"))
  (check-true (string-contains? output "\r\nDate: "))
  (check-true (string-contains? output " GMT\r\n"))
  (check-true
   (string-contains? output "\r\nContent-Type: application/json\r\nContent-Length: 21\r\n\r\n")))

(test-case "a valid traceparent reaches the debug line of the request; an invalid one is ignored"
  (define captured (make-capture))
  (define traced
    (string-append "GET /next HTTP/1.1\r\n"
                   "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01\r\n\r\n"))
  (define invalid "GET /value HTTP/1.1\r\ntraceparent: 00-0000-00f067aa0ba902b7-01\r\n\r\n")
  (serve-on (chunked-input-port (list (string-append traced invalid)))
            (fixture-api (contract))
            (capture-logger captured))
  (define lines (map string->jsexpr (capture-lines captured)))
  (check-equal? (length lines) 2)
  (check-equal? (hash-ref (first lines) 'msg) "request answered")
  (check-equal? (hash-ref (first lines) 'detail) "GET /next -> 200")
  (check-equal? (hash-ref (first lines) 'traceId) "4bf92f3577b34da6a3ce929d0e0e4736")
  (check-equal? (hash-ref (first lines) 'spanId) "00f067aa0ba902b7")
  (check-equal? (hash-ref (second lines) 'traceId) (json-null)))

(test-case "invalid traceparent values are rejected"
  (for ([header (in-list '("" "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7"
                              "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
                              "00-00000000000000000000000000000000-00f067aa0ba902b7-01"
                              "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"
                              "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01"
                              "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-1"))])
    (check-false (parse-traceparent header) header)))

(test-case "log lines are valid JSON with every field of CLAUDE.md 6.1; lower levels are dropped"
  (define captured (make-capture))
  (define log (capture-logger captured 'info))
  (log-write! log 'debug "dropped")
  (log-write! log 'warn "quoted \"msg\"" "line\nbreak\u0001 and ł")
  (log-write! log 'error "traced" #f "4bf92f3577b34da6a3ce929d0e0e4736" "00f067aa0ba902b7")
  (define lines (map string->jsexpr (capture-lines captured)))
  (check-equal? (length lines) 2)
  (define warning (first lines))
  (check-equal? (hash-ref warning 'level) "warn")
  (check-equal? (hash-ref warning 'service) "digit-9")
  (check-equal? (hash-ref warning 'msg) "quoted \"msg\"")
  (check-equal? (hash-ref warning 'detail) "line\nbreak\u0001 and ł")
  (check-equal? (hash-ref warning 'taskId) (json-null))
  (check-equal? (hash-ref warning 'traceId) (json-null))
  (check-equal? (hash-ref warning 'spanId) (json-null))
  (check-equal? (string-length (hash-ref warning 'ts)) 24)
  (check-true (string-suffix? (hash-ref warning 'ts) "Z"))
  (check-equal? (hash-ref (second lines) 'traceId) "4bf92f3577b34da6a3ce929d0e0e4736")
  (check-false (hash-has-key? (second lines) 'detail)))

(test-case "log lines without a sink go to the current output port, one per line"
  (define out (open-output-string))
  (parameterize ([current-output-port out])
    (log-write! (logger "digit-9" 'info #f) 'info "listening" "port 8080"))
  (define text (get-output-string out))
  (check-true (string-suffix? text "}\n"))
  (check-equal? (hash-ref (string->jsexpr text) 'detail) "port 8080"))
