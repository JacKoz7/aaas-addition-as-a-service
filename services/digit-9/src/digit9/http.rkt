#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/http.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         HTTP/1.1 framing of the digit service: buffered line
;;                  reading with a byte budget, request heads, bodies by
;;                  Content-Length or chunked, reply formatting and the
;;                  request loop of one connection.
;; Related Docs:    services/digit-9/README.md, contracts/http/digit.yaml,
;;                  RFC 9110, RFC 9112, ADR-0031

;; The limits are those of the earlier digit services (ADR-0026 to
;; ADR-0030): heads up to 8 KiB (431 above), bodies up to 64 KiB read and
;; discarded (413 above), 400 for a malformed or ambiguous request. A
;; connection is a pair of Racket ports, so the tests use string ports and
;; pipes instead of sockets.

(require racket/string
         "api.rkt"
         "log.rkt"
         "trace.rkt")

(provide max-head
         max-body
         idle-timeout-seconds
         reason
         (struct-out input-reader)
         make-input-reader
         reader-available
         (struct-out line)
         reader-read-line
         reader-skip!
         (struct-out request-head)
         token-char?
         parse-request-line
         parse-header
         has-token?
         keep-alive?
         imf-fixdate
         format-reply
         (struct-out head-result)
         read-head
         read-body
         rejection
         send-all
         serve-connection)

;; Largest request head (request line and header fields), in bytes; a
;; larger head is answered 431.
(define max-head 8192)

;; Largest request body read and discarded, in bytes; a larger one is
;; answered 413 without being read.
(define max-body 65536)

;; Initial size of the input buffer of a connection, and the least free
;; space a receive is given: the buffer is compacted, or its size doubled,
;; when less is free.
(define receive-chunk 4096)

;; Seconds a connection may stay silent, between requests or within one,
;; before it is closed.
(define idle-timeout-seconds 10)

;; The token characters of RFC 9110 other than letters and digits.
(define token-symbols "!#$%&'*+-.^_`|~")

;; The reason phrase of a status the service sends.
;;
;; Business Justification: every status line and problem title names the
;; status in words (RFC 9110, 15).
;;
;; Parameters:
;;   - status: exact-integer; an HTTP status code.
;;
;; Returns: string; the phrase, empty for a status the service never
;; sends.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reason 431)
;;   "Request Header Fields Too Large"
;;   > (reason 299)
;;   ""
(define (reason status)
  (case status
    [(200) "OK"]
    [(400) "Bad Request"]
    [(404) "Not Found"]
    [(405) "Method Not Allowed"]
    [(413) "Content Too Large"]
    [(431) "Request Header Fields Too Large"]
    [(503) "Service Unavailable"]
    [else ""]))

;; Buffered reader of a connection's input.
;;
;; Description: keeps the bytes received but not yet consumed in one buffer
;; per connection, which input is received into directly. When less than
;; `receive-chunk` bytes are free, the unconsumed bytes move to the front,
;; or into a buffer of twice the size when they leave less than that free
;; even at the front; under the head limit the buffer stays at most
;; 16 KiB. After the end of
;; the input, a failure, a timeout or the wake event, every read reports
;; the end.
;;
;; Fields:
;;   - in: input-port; the connection's input.
;;   - timeout: (or/c (>=/c 0) #f); seconds a receive waits for input, or
;;     #f for no limit.
;;   - wake: evt; ends the input when it becomes ready while the reader
;;     waits (the server's stop for idle connections); mutable.
;;   - buffer: bytes; the input buffer; mutable.
;;   - start: exact-nonnegative-integer; the index of the first unconsumed
;;     byte of `buffer`; mutable.
;;   - end: exact-nonnegative-integer; the index after the last received
;;     byte of `buffer`; mutable.
;;   - ended?: boolean; #t once the input ended, failed, timed out or was
;;     woken; mutable.
;;
;; Business Justification: requests may arrive split across packets or
;; several in one packet (pipelining); one reused buffer keeps the memory
;; of 256 connections small and the garbage of a flood low (ADR-0031).
;;
;; Thread Safety: one thread per connection; `wake` is only set by that
;; thread. Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reader-available (make-input-reader (open-input-bytes #"GET")))
;;   0
(struct input-reader
        (in timeout
            [wake #:mutable]
            [buffer #:mutable]
            [start #:mutable]
            [end #:mutable]
            [ended? #:mutable]))

;; Create a reader of an input port.
;;
;; Business Justification: one reader per connection bounds what the service
;; buffers for a client.
;;
;; Parameters:
;;   - in: input-port; the connection's input.
;;   - timeout: (or/c (>=/c 0) #f); seconds a receive waits; by default
;;     `idle-timeout-seconds`.
;;   - wake: evt; ends the input while the reader waits; `never-evt` by
;;     default.
;;
;; Returns: input-reader; a reader with an empty buffer.
;;
;; Errors: none. Side Effects: allocates the 4 KiB input buffer.
;; Complexity: O(1). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (input-reader-timeout (make-input-reader (open-input-bytes #"") #:timeout 1))
;;   1
(define (make-input-reader in #:timeout [timeout idle-timeout-seconds] #:wake [wake never-evt])
  (input-reader in timeout wake (make-bytes receive-chunk) 0 0 #f))

;; Number of bytes received but not consumed.
;;
;; Business Justification: the head limit counts the bytes a client sent but
;; the service has not consumed.
;;
;; Parameters:
;;   - reader: input-reader; the reader.
;;
;; Returns: exact-nonnegative-integer; the count.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: one
;; thread. Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define pending (make-input-reader (open-input-bytes #"ab\ncd")))
;;   > (line-text (reader-read-line pending 100))
;;   "ab"
;;   > (reader-available pending)
;;   2
(define (reader-available reader)
  (- (input-reader-end reader) (input-reader-start reader)))

;; Make at least `receive-chunk` bytes free at the end of the buffer.
;;
;; Description: moves the unconsumed bytes to the front of the buffer, or
;; into a new buffer of twice the size (at least the unconsumed bytes and
;; one chunk) when they would leave less than a chunk free.
;;
;; Parameters:
;;   - reader: input-reader; the reader.
;;
;; Returns: void.
;;
;; Errors: none. Side Effects: may replace the buffer. Complexity: O(n) in
;; the unconsumed bytes. Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define growing (make-input-reader (open-input-bytes (make-bytes 6000 65))))
;;   > (reader-read-line growing 10000)
;;   (line 'closed "" 0)
;;   > (bytes-length (input-reader-buffer growing))
;;   16384
(define (make-room! reader)
  (define buffer (input-reader-buffer reader))
  (define start (input-reader-start reader))
  (define pending (reader-available reader))
  (when (< (- (bytes-length buffer) (input-reader-end reader)) receive-chunk)
    (define target
      (if (<= (+ pending receive-chunk) (bytes-length buffer))
          buffer
          (make-bytes (max (* 2 (bytes-length buffer)) (+ pending receive-chunk)))))
    (bytes-copy! target 0 buffer start (+ start pending))
    (set-input-reader-buffer! reader target)
    (set-input-reader-start! reader 0)
    (set-input-reader-end! reader pending)))

;; Wait for input and receive what is available into the free space of
;; the buffer.
;;
;; Description: waits up to the timeout for the input or the wake event;
;; a failed read (for example a reset or a closed port) counts as the end.
;;
;; Parameters:
;;   - reader: input-reader; the reader.
;;
;; Returns: exact-nonnegative-integer; the bytes received after `end`, 0 at
;; the end of the input, on a failure, a timeout or the wake event.
;;
;; Errors: none (0). Side Effects: reads the port; writes the buffer.
;; Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (receive! (make-input-reader (open-input-bytes #"GET")))
;;   3
(define (receive! reader)
  (define in (input-reader-in reader))
  (define buffer (input-reader-buffer reader))
  (with-handlers ([exn:fail? (lambda (_) 0)])
    (let loop ()
      (define ready (sync/timeout (input-reader-timeout reader) in (input-reader-wake reader)))
      (cond
        [(not (eq? ready in)) 0]
        [else
         (define count
           (read-bytes-avail!* buffer in (input-reader-end reader) (bytes-length buffer)))
         (cond
           [(eqv? count 0) (loop)]
           [(exact-positive-integer? count) count]
           [else 0])]))))

;; Receive more input into the buffer.
;;
;; Description: makes room first (see make-room!), so the buffer never
;; holds more than the unconsumed input and the space for one receive.
;;
;; Parameters:
;;   - reader: input-reader; the reader.
;;
;; Returns: boolean; #f at the end of the input, on a failure, a timeout
;; or the wake event.
;;
;; Errors: none. Side Effects: reads the port. Complexity: O(n) in the
;; unconsumed bytes. Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define filling (make-input-reader (open-input-bytes #"x")))
;;   > (fill! filling)
;;   #t
;;   > (fill! filling)
;;   #f
(define (fill! reader)
  (cond
    [(input-reader-ended? reader) #f]
    [else
     (make-room! reader)
     (define count (receive! reader))
     (cond
       [(zero? count)
        (set-input-reader-ended?! reader #t)
        #f]
       [else
        (set-input-reader-end! reader (+ (input-reader-end reader) count))
        #t])]))

;; One line read by `reader-read-line`.
;;
;; Business Justification: the framing tells a complete line from a closed
;; or oversized one without exceptions.
;;
;; Fields:
;;   - status: symbol; `ok` (a line was read), `closed` (the input ended,
;;     failed or stayed silent past the timeout) or `too-large` (the line
;;     is longer than the bytes still allowed).
;;   - text: string; the line without its line ending, ISO 8859-1 decoded;
;;     empty unless `status` is `ok`.
;;   - used: exact-nonnegative-integer; the bytes the line took, its line
;;     ending included; 0 unless `status` is `ok`.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (line-status (line 'closed "" 0))
;;   'closed
(struct line (status text used) #:transparent)

;; The index of the first occurrence of a byte in a range.
;;
;; Parameters:
;;   - bytes: bytes; the bytes searched.
;;   - byte: byte; the value looked for.
;;   - start: exact-nonnegative-integer; the first index searched.
;;   - end: exact-nonnegative-integer; the index after the last one
;;     searched.
;;
;; Returns: (or/c exact-nonnegative-integer? #f); the index, or #f.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (find-byte #"a\nb\n" 10 2 4)
;;   3
;;   > (find-byte #"a\nb\n" 10 2 3)
;;   #f
(define (find-byte bytes byte start end)
  (for/first ([index (in-range start end)]
              #:when (= (bytes-ref bytes index) byte))
    index))

;; Read one line.
;;
;; Description: lines end with LF, optionally preceded by CR, which is
;; removed. `budget` is the number of bytes the line may take, its line
;; ending included.
;;
;; Business Justification: bounds the memory a client can make the
;; service hold.
;;
;; Parameters:
;;   - reader: input-reader; the reader.
;;   - budget: exact-nonnegative-integer; the bytes still allowed.
;;
;; Returns: line; the line, or the status `closed` or `too-large`.
;;
;; Errors: none (the status). Side Effects: reads the port.
;; Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reader-read-line (make-input-reader (open-input-bytes #"GET / HTTP/1.1\r\n")) 100)
;;   (line 'ok "GET / HTTP/1.1" 16)
;;   > (reader-read-line (make-input-reader (open-input-bytes #"GET / HTTP/1.1\r\n")) 10)
;;   (line 'too-large "" 0)
;;   > (reader-read-line (make-input-reader (open-input-bytes #"GET")) 10)
;;   (line 'closed "" 0)
(define (reader-read-line reader budget)
  (let loop ([scanned 0])
    (define buffer (input-reader-buffer reader))
    (define start (input-reader-start reader))
    (define lf (find-byte buffer 10 (+ start scanned) (input-reader-end reader)))
    (cond
      [lf
       (define used (+ (- lf start) 1))
       (cond
         [(> used budget) (line 'too-large "" 0)]
         [else
          (define stop
            (if (and (> lf start) (= (bytes-ref buffer (- lf 1)) 13))
                (- lf 1)
                lf))
          (define text (bytes->string/latin-1 (subbytes buffer start stop)))
          (set-input-reader-start! reader (+ lf 1))
          (line 'ok text used)])]
      [(> (reader-available reader) budget) (line 'too-large "" 0)]
      [else
       (define searched (reader-available reader))
       (if (fill! reader)
           (loop searched)
           (line 'closed "" 0))])))

;; Read and discard bytes.
;;
;; Business Justification: a body is discarded without being kept in memory.
;;
;; Parameters:
;;   - reader: input-reader; the reader.
;;   - count: exact-nonnegative-integer; the bytes to skip.
;;
;; Returns: boolean; #t when all bytes were read.
;;
;; Errors: none (#f when the input ends early). Side Effects: reads the
;; port. Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reader-skip! (make-input-reader (open-input-bytes #"hello")) 5)
;;   #t
;;   > (reader-skip! (make-input-reader (open-input-bytes #"hello")) 6)
;;   #f
(define (reader-skip! reader count)
  (let loop ([left count])
    (define take (min left (reader-available reader)))
    (set-input-reader-start! reader (+ (input-reader-start reader) take))
    (cond
      [(= left take) #t]
      [(fill! reader) (loop (- left take))]
      [else #f])))

;; A parsed request head.
;;
;; Business Justification: the parts of a request the contract and the
;; framing decide on.
;;
;; Fields:
;;   - method: string; the method, as received.
;;   - target: string; the request target (path and query).
;;   - minor: string; the minor HTTP version, "0" or "1".
;;   - headers: (hash/c string? string?); the header fields by lower-case
;;     name (immutable), repeated fields joined by commas.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (request-head-minor (request-head "GET" "/" "1" (hash)))
;;   "1"
(struct request-head (method target minor headers) #:transparent)

;; Whether a character is an RFC 9110 token character (tchar).
;;
;; Business Justification: methods and header names are validated before
;; they are trusted (RFC 9110, 5.6.2).
;;
;; Parameters:
;;   - c: char; the character.
;;
;; Returns: boolean; #t for an ASCII letter, digit or token symbol.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (and (token-char? #\G) (token-char? #\~))
;;   #t
;;   > (or (token-char? #\space) (token-char? #\:) (token-char? #\é))
;;   #f
(define (token-char? c)
  (or (char<=? #\a c #\z)
      (char<=? #\A c #\Z)
      (char<=? #\0 c #\9)
      (for/or ([symbol (in-string token-symbols)])
        (char=? c symbol))))

;; Whether a string is a non-empty token.
;;
;; Parameters:
;;   - text: string; the text.
;;
;; Returns: boolean; #t when it is non-empty and every character is a
;; token character.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (token? "Content-Length")
;;   #t
;;   > (token? "")
;;   #f
(define (token? text)
  (and (positive? (string-length text))
       (for/and ([c (in-string text)])
         (token-char? c))))

;; Parse a request line.
;;
;; Description: the line must be method SP request-target SP HTTP-version,
;; where the method is a token (RFC 9110 tchar), the target has no spaces
;; or control characters and the version is HTTP/1.0 or HTTP/1.1. The
;; trailing CR LF must already be removed.
;;
;; Business Justification: a malformed request is answered 400 instead of
;; being guessed at.
;;
;; Parameters:
;;   - text: string; the request line without CR LF.
;;
;; Returns: (or/c request-head? #f); the method, the target and the minor
;; version with no headers, or #f when the line is invalid.
;;
;; Errors: none (#f). Side Effects: none. Complexity: O(n).
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (parse-request-line "GET /next?x=1 HTTP/1.1")
;;   (request-head "GET" "/next?x=1" "1" '#hash())
;;   > (parse-request-line "GET  /next HTTP/1.1")
;;   #f
;;   > (parse-request-line "PRI * HTTP/2.0")
;;   #f
;;
;; See Also: parse-header.
(define (parse-request-line text)
  (define parts (string-split text " " #:trim? #f))
  (and (= (length parts) 3)
       (let ([method (car parts)]
             [target (cadr parts)]
             [version (caddr parts)])
         (and (token? method)
              (positive? (string-length target))
              (for/and ([c (in-string target)])
                (and (char>? c #\space) (not (char=? c #\rubout))))
              (member version '("HTTP/1.0" "HTTP/1.1"))
              (request-head method target (substring version 7) (hash))))))

;; Remove spaces and tabs at both ends of a string (optional whitespace,
;; RFC 9110 5.6.3).
;;
;; Parameters:
;;   - text: string; the text.
;;
;; Returns: string; the text without leading and trailing spaces and tabs.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (trim-ows " \t5 ")
;;   "5"
(define (trim-ows text)
  (string-trim text #px"[ \t]+"))

;; Parse a header field line.
;;
;; Description: name ":" OWS value OWS; the name is a token and is
;; returned in lower case. Obsolete line folding (a line starting with a
;; space) is rejected, because a space is not a token character.
;;
;; Business Justification: header fields decide the body length, the
;; persistence of the connection and the trace context.
;;
;; Parameters:
;;   - text: string; the header line without CR LF.
;;
;; Returns: (or/c (cons/c string? string?) #f); the lower-case name and the
;; value without surrounding spaces and tabs, or #f when the line is
;; invalid.
;;
;; Errors: none (#f). Side Effects: none. Complexity: O(n).
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (parse-header "Content-Length: \t5 ")
;;   '("content-length" . "5")
;;   > (parse-header " folded: x")
;;   #f
;;   > (parse-header ": x")
;;   #f
(define (parse-header text)
  (define colon
    (for/first ([c (in-string text)]
                [index (in-naturals)]
                #:when (char=? c #\:))
      index))
  (and colon
       (token? (substring text 0 colon))
       (cons (string-downcase (substring text 0 colon)) (trim-ows (substring text (+ colon 1))))))

;; Whether a comma-separated header value contains a token.
;;
;; Business Justification: Connection header values decide the persistence
;; of the connection.
;;
;; Parameters:
;;   - value: (or/c string? #f); the header value, or #f when absent.
;;   - token: string; the lower-case token.
;;
;; Returns: boolean; #t when present (case-insensitive).
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (has-token? "keep-alive, Close" "close")
;;   #t
;;   > (has-token? "closed" "close")
;;   #f
;;   > (has-token? #f "close")
;;   #f
(define (has-token? value token)
  (and value
       (for/or ([part (in-list (string-split (string-downcase value) "," #:trim? #f))])
         (string=? (trim-ows part) token))))

;; Whether the connection stays open after the reply.
;;
;; Description: HTTP/1.1 keeps it unless the request says Connection:
;; close; HTTP/1.0 keeps it only with Connection: keep-alive.
;;
;; Business Justification: callers reuse connections, which saves a TCP
;; handshake per digit call.
;;
;; Parameters:
;;   - minor: string; the minor HTTP version, "0" or "1".
;;   - headers: (hash/c string? string?); the header fields by lower-case
;;     name.
;;
;; Returns: boolean; #t to keep the connection.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (keep-alive? "1" (hash))
;;   #t
;;   > (keep-alive? "1" (hash "connection" "close"))
;;   #f
;;   > (keep-alive? "0" (hash))
;;   #f
;;   > (keep-alive? "0" (hash "connection" "Keep-Alive"))
;;   #t
(define (keep-alive? minor headers)
  (define connection (hash-ref headers "connection" #f))
  (if (string=? minor "1")
      (not (has-token? connection "close"))
      (has-token? connection "keep-alive")))

;; Format a time in the IMF-fixdate format of the Date header (RFC 9110,
;; 5.6.7).
;;
;; Business Justification: every reply carries a Date header (RFC 9110,
;; 6.6.1).
;;
;; Parameters:
;;   - seconds: exact-integer; seconds since the Unix epoch; by default the
;;     current time.
;;
;; Returns: string; for example `Sun, 25 Oct 2026 12:00:05 GMT`.
;;
;; Errors: none. Side Effects: reads the clock when `seconds` is not
;; given. Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (imf-fixdate 1792929605)
;;   "Sun, 25 Oct 2026 12:00:05 GMT"
(define (imf-fixdate [seconds (current-seconds)])
  (define time (seconds->date seconds #f))
  (string-append
   (list-ref '("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat") (date-week-day time))
   ", "
   (pad-number (date-day time) 2)
   " "
   (list-ref '("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec")
             (- (date-month time) 1))
   " "
   (pad-number (date-year time) 4)
   " "
   (pad-number (date-hour time) 2)
   ":"
   (pad-number (date-minute time) 2)
   ":"
   (pad-number (date-second time) 2)
   " GMT"))

;; Serialise a reply.
;;
;; Description: status line, Date, Content-Type, Content-Length (of the
;; UTF-8 body), Allow when the reply has one and Connection: close when
;; the connection ends; the body is left out for HEAD.
;;
;; Business Justification: one place produces the bytes of every answer.
;;
;; Parameters:
;;   - answer: reply; the reply.
;;   - head?: boolean; #t for a HEAD request.
;;   - close?: boolean; #t when the connection is closed after the reply.
;;
;; Returns: bytes; the response.
;;
;; Errors: none. Side Effects: reads the clock. Complexity: O(n) in the
;; body. Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (regexp-match? #rx#"^HTTP/1.1 405 Method Not Allowed\r\nDate: "
;;                    (format-reply (reply 405 problem-type "{}" "GET") #f #t))
;;   #t
;;   > (regexp-match? #rx#"Content-Length: 2\r\nAllow: GET\r\nConnection: close\r\n\r\n{}$"
;;                    (format-reply (reply 405 problem-type "{}" "GET") #f #t))
;;   #t
;;   > (regexp-match? #rx#"Content-Length: 2\r\n\r\n$"
;;                    (format-reply (reply 200 json-type "{}" #f) #t #f))
;;   #t
(define (format-reply answer head? close?)
  (define body (string->bytes/utf-8 (reply-body answer)))
  (define allow (reply-allow answer))
  (bytes-append (string->bytes/latin-1 (string-append "HTTP/1.1 "
                                                      (number->string (reply-status answer))
                                                      " "
                                                      (reason (reply-status answer))
                                                      "\r\nDate: "
                                                      (imf-fixdate)
                                                      "\r\nContent-Type: "
                                                      (reply-content-type answer)
                                                      "\r\nContent-Length: "
                                                      (number->string (bytes-length body))
                                                      "\r\n"
                                                      (if allow
                                                          (string-append "Allow: " allow "\r\n")
                                                          "")
                                                      (if close? "Connection: close\r\n" "")
                                                      "\r\n"))
                (if head? #"" body)))

;; The result of `read-head`.
;;
;; Business Justification: tells the request loop whether to answer, reject
;; or end the connection.
;;
;; Fields:
;;   - head: (or/c request-head? #f); the head, set only when `status` is 0
;;     and `ended?` is #f.
;;   - status: exact-integer; 0 for a head, otherwise the error status (400
;;     or 431).
;;   - ended?: boolean; #t for a clean end: the client closed or went
;;     silent before the request line was complete.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (head-result-status (head-result #f 431 #f))
;;   431
(struct head-result (head status ended?) #:transparent)

;; Read a request head.
;;
;; Description: skips empty lines before the request line (RFC 9112, 2.2),
;; then reads header fields up to the empty line. Repeated fields are
;; joined with a comma.
;;
;; Business Justification: bounds what a client can make the service read
;; before it answers.
;;
;; Parameters:
;;   - reader: input-reader; the connection's input.
;;
;; Returns: head-result; the head, a clean end, or the error status: 400
;; for a malformed head or one cut short after the request line, 431 for a
;; head above `max-head`.
;;
;; Errors: none (the status). Side Effects: reads the port.
;; Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (read-head (make-input-reader
;;                 (open-input-bytes #"\r\nGET /next HTTP/1.1\r\nA: 1\r\na: 2\r\n\r\n")))
;;   (head-result (request-head "GET" "/next" "1" '#hash(("a" . "1, 2"))) 0 #f)
;;   > (read-head (make-input-reader (open-input-bytes #"")))
;;   (head-result #f 0 #t)
(define (read-head reader)
  (let skip-empty ([budget max-head])
    (define opening (reader-read-line reader budget))
    (case (line-status opening)
      [(too-large) (head-result #f 431 #f)]
      [(closed) (head-result #f 0 #t)]
      [else
       (define left (- budget (line-used opening)))
       (cond
         [(zero? (string-length (line-text opening))) (skip-empty left)]
         [(parse-request-line (line-text opening))
          =>
          (lambda (start)
            (let fields ([budget left]
                         [headers (hash)])
              (define field (reader-read-line reader budget))
              (cond
                [(eq? (line-status field) 'too-large) (head-result #f 431 #f)]
                [(eq? (line-status field) 'closed) (head-result #f 400 #f)]
                [(zero? (string-length (line-text field)))
                 (head-result (struct-copy request-head start [headers headers]) 0 #f)]
                [(parse-header (line-text field))
                 =>
                 (lambda (pair)
                   (define existing (hash-ref headers (car pair) #f))
                   (fields (- budget (line-used field))
                           (hash-set headers
                                     (car pair)
                                     (if existing
                                         (string-append existing ", " (cdr pair))
                                         (cdr pair)))))]
                [else (head-result #f 400 #f)])))]
         [else (head-result #f 400 #f)])])))

;; The length of the leading hexadecimal digits of a string.
;;
;; Parameters:
;;   - text: string; the text.
;;
;; Returns: exact-nonnegative-integer; the number of leading characters
;; that are hexadecimal digits (either case).
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (hex-prefix-length "1aF;ext")
;;   3
(define (hex-prefix-length text)
  (or (for/first ([c (in-string text)]
                  [index (in-naturals)]
                  #:unless (or (char<=? #\0 c #\9) (char<=? #\a c #\f) (char<=? #\A c #\F)))
        index)
      (string-length text)))

;; Read and discard a chunked body and its trailer section.
;;
;; Parameters:
;;   - reader: input-reader; the connection's input.
;;
;; Returns: exact-integer; 0 when the body was skipped, 400 for a malformed
;; or truncated body, 413 when its chunks add up to more than `max-body`.
;;
;; Errors: none (the status). Side Effects: reads the port.
;; Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (skip-chunked (make-input-reader (open-input-bytes #"3\r\nabc\r\n0\r\n\r\n")))
;;   0
(define (skip-chunked reader)
  (let chunks ([total 0])
    (define size-line (reader-read-line reader max-head))
    (define digits
      (and (eq? (line-status size-line) 'ok) (hex-prefix-length (line-text size-line))))
    (cond
      [(not (and digits (<= 1 digits 8))) 400]
      [else
       (define size (string->number (substring (line-text size-line) 0 digits) 16))
       (define sum (+ total size))
       (cond
         [(> sum max-body) 413]
         [(zero? size)
          (let trailers ()
            (define trailer (reader-read-line reader max-head))
            (cond
              [(not (eq? (line-status trailer) 'ok)) 400]
              [(zero? (string-length (line-text trailer))) 0]
              [else (trailers)]))]
         [(not (reader-skip! reader size)) 400]
         [else
          (define end (reader-read-line reader 2))
          (if (and (eq? (line-status end) 'ok) (zero? (string-length (line-text end))))
              (chunks sum)
              400)])])))

;; Read and discard the request body.
;;
;; Description: Content-Length bodies up to `max-body` are skipped;
;; chunked bodies are skipped chunk by chunk with the same total limit
;; (trailer fields are read and ignored). A request with both
;; Content-Length and Transfer-Encoding, another transfer coding or an
;; invalid length is malformed (RFC 9112, 6.1 and 6.3).
;;
;; Business Justification: the contract has no request bodies, but a body
;; sent anyway must not be mistaken for the next request.
;;
;; Parameters:
;;   - reader: input-reader; the connection's input.
;;   - headers: (hash/c string? string?); the header fields by lower-case
;;     name.
;;
;; Returns: exact-integer; 0 when the body was skipped, otherwise the error
;; status: 400 for a malformed or truncated body, 413 for one above
;; `max-body`.
;;
;; Errors: none (the status). Side Effects: reads the port.
;; Complexity: O(n). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (read-body (make-input-reader (open-input-bytes #"")) (hash "content-length" "70000"))
;;   413
;;   > (read-body (make-input-reader (open-input-bytes #""))
;;                (hash "content-length" "1" "transfer-encoding" "chunked"))
;;   400
(define (read-body reader headers)
  (define length-value (hash-ref headers "content-length" #f))
  (define coding (hash-ref headers "transfer-encoding" #f))
  (cond
    [coding
     (if (or length-value (not (string-ci=? coding "chunked")))
         400
         (skip-chunked reader))]
    [(not length-value) 0]
    [(not (and (<= 1 (string-length length-value) 9)
               (for/and ([c (in-string length-value)])
                 (char<=? #\0 c #\9))))
     400]
    [(> (string->number length-value) max-body) 413]
    [(reader-skip! reader (string->number length-value)) 0]
    [else 400]))

;; The problem details reply for a rejected request.
;;
;; Business Justification: malformed requests are answered with problem
;; details like every AaaS error (CLAUDE.md 4.1).
;;
;; Parameters:
;;   - status: exact-integer; 400, 413 or 431.
;;
;; Returns: reply; the reply.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (reply-status (rejection 413))
;;   413
;;   > (reply-allow (rejection 413))
;;   #f
(define (rejection status)
  (problem status (reason status) "the request is malformed or too large"))

;; Write all bytes to an output port and flush it.
;;
;; Business Justification: a client that disappears ends its connection
;; instead of failing the service.
;;
;; Parameters:
;;   - out: output-port; the connection's output.
;;   - bytes: bytes; the bytes.
;;
;; Returns: boolean; #t when every byte was written and flushed, #f when
;; the port failed (for example a reset connection).
;;
;; Errors: none (#f). Side Effects: writes the port. Complexity: O(n).
;; Thread Safety: one thread. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (send-all (open-output-bytes) #"HTTP/1.1 200 OK\r\n")
;;   #t
(define (send-all out bytes)
  (with-handlers ([exn:fail? (lambda (_) #f)])
    (write-bytes bytes out)
    (flush-output out)
    #t))

;; Answer a rejected request, log it and end the connection.
;;
;; Parameters:
;;   - out: output-port; the connection's output.
;;   - status: exact-integer; 400, 413 or 431.
;;   - log: logger; the logger.
;;
;; Returns: void.
;;
;; Errors: none. Side Effects: writes the port; logs at debug level.
;; Complexity: O(1). Thread Safety: one thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define rejected (open-output-bytes))
;;   > (reject! rejected 431 (logger "digit-9" 'error #f))
;;   > (regexp-match? #rx#"^HTTP/1.1 431 " (get-output-bytes rejected))
;;   #t
(define (reject! out status log)
  (send-all out (format-reply (rejection status) #f #t))
  (log-write! log 'debug "request rejected" (number->string status)))

;; Serve the requests of one connection until it ends.
;;
;; Description: reads a head, skips the body, asks `handler` for the
;; reply, logs it at debug level with the trace context and sends it;
;; repeats while the connection is persistent and `stopping?` returns #f.
;; Malformed requests are answered 400, 413 or 431 with problem details
;; and end the connection. From the end of a head to the reply, the
;; reader's wake event is set aside, so a stop wakes only idle connections
;; and never cuts a request short.
;;
;; Business Justification: the transport of the digit contract.
;;
;; Parameters:
;;   - reader: input-reader; the connection's input.
;;   - out: output-port; the connection's output.
;;   - handler: (-> string? string? reply?); the reply for a method and a
;;     path.
;;   - stopping?: (-> boolean?); returns #t once the server stops.
;;   - log: logger; the logger.
;;
;; Returns: void.
;;
;; Errors: none (write failures end the connection). Side Effects: reads
;; and writes the ports; calls `handler`; logs. Complexity: O(n) per
;; request. Thread Safety: one thread per connection.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define served (open-output-bytes))
;;   > (serve-connection (make-input-reader (open-input-bytes #"GET /x HTTP/1.1\r\n\r\n"))
;;                       served
;;                       (lambda (method path) (reply 200 json-type "{}" #f))
;;                       (lambda () #f)
;;                       (logger "digit-9" 'error #f))
;;   > (regexp-match? #rx#"^HTTP/1.1 200 OK\r\n.*\r\n\r\n{}$" (get-output-bytes served))
;;   #t
;;
;; See Also: api-handle.
(define (serve-connection reader out handler stopping? log)
  (define idle-wake (input-reader-wake reader))
  (let loop ()
    (define result (read-head reader))
    (cond
      [(head-result-ended? result) (void)]
      [(not (zero? (head-result-status result))) (reject! out (head-result-status result) log)]
      [else
       (define head (head-result-head result))
       (set-input-reader-wake! reader never-evt)
       (define body-status (read-body reader (request-head-headers head)))
       (cond
         [(not (zero? body-status)) (reject! out body-status log)]
         [else
          (define target (request-head-target head))
          (define path (car (string-split target "?" #:trim? #f)))
          (define method (request-head-method head))
          (define answer (handler method path))
          (define keep?
            (and (keep-alive? (request-head-minor head) (request-head-headers head))
                 (not (stopping?))))
          (define trace (parse-traceparent (hash-ref (request-head-headers head) "traceparent" #f)))
          (log-write! log
                      'debug
                      "request answered"
                      (string-append method " " path " -> " (number->string (reply-status answer)))
                      (and trace (trace-context-trace-id trace))
                      (and trace (trace-context-span-id trace)))
          (define sent? (send-all out (format-reply answer (string=? method "HEAD") (not keep?))))
          (set-input-reader-wake! reader idle-wake)
          (when (and sent? keep?)
            (loop))])])))
