#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/log.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Structured JSON log lines on stdout with the fields of
;;                  CLAUDE.md 6.1 (ts, level, service, msg, taskId, traceId,
;;                  spanId).
;; Related Docs:    services/digit-9/README.md, CLAUDE.md 6.1, ADR-0031

;; Every line is one JSON object written and flushed under one lock, so the
;; lines of concurrent connection threads never interleave. The digit
;; service has no task, so `taskId` is always `null`.

(provide level-name
         parse-level
         json-escape
         timestamp
         format-timestamp
         pad-number
         (struct-out logger)
         logger-format
         log-write!)

;; The levels, from the most verbose to the most severe: `debug` (one line
;; per request), `info` (lifecycle), `warn` (degraded but serving) and
;; `error` (a failure).
(define levels '(debug info warn error))

;; Serialises the writes of log lines to stdout across threads.
(define output-lock (make-semaphore 1))

;; The name of a level as written in the `level` field.
;;
;; Business Justification: operators filter the log stream by level
;; (`AAAS_LOG_LEVEL`); the names are those of every AaaS service.
;;
;; Parameters:
;;   - level: symbol; one of `debug`, `info`, `warn` or `error`.
;;
;; Returns: string; the name of the level.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (level-name 'warn)
;;   "warn"
(define (level-name level)
  (symbol->string level))

;; Parse a level name, falling back for an unknown or empty name.
;;
;; Business Justification: a mistyped `AAAS_LOG_LEVEL` must not stop the
;; service; it logs at the fallback level instead.
;;
;; Parameters:
;;   - name: string; the configured name (lower case).
;;   - fallback: symbol; the level used when `name` is not a level name.
;;
;; Returns: symbol; the level.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (parse-level "debug" 'info)
;;   'debug
;;   > (parse-level "verbose" 'info)
;;   'info
(define (parse-level name fallback)
  (or (for/first ([level (in-list levels)]
                  #:when (string=? (level-name level) name))
        level)
      fallback))

;; The position of a level in `levels`, for comparisons.
;;
;; Parameters:
;;   - level: symbol; a level.
;;
;; Returns: exact-nonnegative-integer; 0 for `debug` up to 3 for `error`.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (level-rank 'warn)
;;   2
(define (level-rank level)
  (for/first ([candidate (in-list levels)]
              [rank (in-naturals)]
              #:when (eq? candidate level))
    rank))

;; Format a natural number in decimal, padded with zeros to a width.
;;
;; Business Justification: timestamps and dates have fixed-width fields.
;;
;; Parameters:
;;   - number: exact-nonnegative-integer; the number.
;;   - width: exact-positive-integer; the minimal number of digits.
;;
;; Returns: string; the digits, with leading zeros up to `width`.
;;
;; Errors: none. Side Effects: none. Complexity: O(w). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (pad-number 7 3)
;;   "007"
;;   > (pad-number 2026 2)
;;   "2026"
(define (pad-number number width)
  (define digits (number->string number))
  (if (< (string-length digits) width)
      (string-append (make-string (- width (string-length digits)) #\0) digits)
      digits))

;; Escape a string for a JSON string literal (RFC 8259).
;;
;; Description: escapes `"` and `\`, writes newline, return and tab in
;; short form and every other control character below U+0020 as `\u00xx`.
;; Other characters are copied unchanged.
;;
;; Business Justification: a log line or problem detail that quotes a
;; value must stay valid JSON whatever the value holds.
;;
;; Parameters:
;;   - text: string; any text.
;;
;; Returns: string; the escaped text, without the surrounding quotes.
;;
;; Errors: none. Side Effects: none. Complexity: O(n) time and memory.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (json-escape "a\"b\\c")
;;   "a\\\"b\\\\c"
;;   > (json-escape "tab\there\u0001")
;;   "tab\\there\\u0001"
;;   > (json-escape "zażółć")
;;   "zażółć"
(define (json-escape text)
  (define out (open-output-string))
  (for ([c (in-string text)])
    (case c
      [(#\") (write-string "\\\"" out)]
      [(#\\) (write-string "\\\\" out)]
      [(#\newline) (write-string "\\n" out)]
      [(#\return) (write-string "\\r" out)]
      [(#\tab) (write-string "\\t" out)]
      [else
       (if (char<? c #\space)
           (write-string (string-append "\\u00" (hex-byte (char->integer c))) out)
           (write-char c out))]))
  (get-output-string out))

;; Two lower-case hexadecimal digits of a byte.
;;
;; Parameters:
;;   - byte: byte; the value, 0..255.
;;
;; Returns: string; two hexadecimal digits.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (hex-byte 31)
;;   "1f"
(define (hex-byte byte)
  (define digits (number->string byte 16))
  (if (= (string-length digits) 1)
      (string-append "0" digits)
      digits))

;; A JSON string literal, or `null` for an absent value.
;;
;; Parameters:
;;   - value: (or/c string? #f); the text, or #f when absent.
;;
;; Returns: string; `"..."` or `null`.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (quoted #f)
;;   "null"
;;   > (quoted "")
;;   "\"\""
(define (quoted value)
  (if value
      (string-append "\"" (json-escape value) "\"")
      "null"))

;; The current UTC time in RFC 3339 with milliseconds.
;;
;; Business Justification: the `ts` field must be comparable across the 35
;; services; every service writes UTC with a `Z` suffix.
;;
;; Parameters: none.
;;
;; Returns: string; for example `2026-10-25T16:20:01.123Z`.
;;
;; Errors: none. Side Effects: reads the clock. Complexity: O(1).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (string-length (timestamp))
;;   24
(define (timestamp)
  (format-timestamp (inexact->exact (floor (current-inexact-milliseconds)))))

;; Format a time as RFC 3339 UTC with milliseconds.
;;
;; Business Justification: the `ts` field of every log line (CLAUDE.md 6.1).
;;
;; Parameters:
;;   - milliseconds: exact-nonnegative-integer; milliseconds since the Unix
;;     epoch.
;;
;; Returns: string; `YYYY-MM-DDTHH:MM:SS.mmmZ`.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (format-timestamp 1792945321123)
;;   "2026-10-25T16:22:01.123Z"
(define (format-timestamp milliseconds)
  (define time (seconds->date (quotient milliseconds 1000) #f))
  (string-append (pad-number (date-year time) 4)
                 "-"
                 (pad-number (date-month time) 2)
                 "-"
                 (pad-number (date-day time) 2)
                 "T"
                 (pad-number (date-hour time) 2)
                 ":"
                 (pad-number (date-minute time) 2)
                 ":"
                 (pad-number (date-second time) 2)
                 "."
                 (pad-number (remainder milliseconds 1000) 3)
                 "Z"))

;; A logger bound to one service name and a threshold.
;;
;; Description: `sink` replaces stdout when set (the tests capture lines
;; with it); lines below `threshold` are dropped.
;;
;; Fields:
;;   - service: string; the service name written in the `service` field.
;;   - threshold: symbol; the lowest level written.
;;   - sink: (or/c (-> string? any) #f); receives each line (without a
;;     newline) instead of stdout, or #f for stdout.
;;
;; Business Justification: every line of every AaaS service carries the
;; fields of CLAUDE.md 6.1.
;;
;; Thread Safety: immutable; `log-write!` may be called from any thread.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (logger-service (logger "digit-9" 'info #f))
;;   "digit-9"
(struct logger (service threshold sink))

;; Format one log line without writing it.
;;
;; Description: the fields are `ts`, `level`, `service`, `msg`, `taskId`
;; (always `null`), `traceId`, `spanId` and, when given, `detail`.
;;
;; Business Justification: the tests check the fields of a line without
;; writing it.
;;
;; Parameters:
;;   - log: logger; the logger.
;;   - level: symbol; the severity.
;;   - msg: string; the fixed message.
;;   - detail: (or/c string? #f); the variable detail, or #f.
;;   - trace-id: (or/c string? #f); the caller's trace identifier, or #f.
;;   - span-id: (or/c string? #f); the caller's span identifier, or #f.
;;
;; Returns: string; the JSON object, without a newline.
;;
;; Errors: none. Side Effects: reads the clock. Complexity: O(n) in the
;; length of the fields. Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define line (logger-format (logger "digit-9" 'info #f) 'info "up" #f #f #f))
;;   > (substring line 33 79)
;;   "\"level\":\"info\",\"service\":\"digit-9\",\"msg\":\"up\","
;;   > (substring line 79)
;;   "\"taskId\":null,\"traceId\":null,\"spanId\":null}"
(define (logger-format log level msg detail trace-id span-id)
  (string-append "{\"ts\":\""
                 (timestamp)
                 "\",\"level\":\""
                 (level-name level)
                 "\",\"service\":"
                 (quoted (logger-service log))
                 ",\"msg\":"
                 (quoted msg)
                 ",\"taskId\":null,\"traceId\":"
                 (quoted trace-id)
                 ",\"spanId\":"
                 (quoted span-id)
                 (if detail
                     (string-append ",\"detail\":" (quoted detail))
                     "")
                 "}"))

;; Write one log line if its level reaches the threshold.
;;
;; Description: the line goes to the sink when one is set, otherwise to
;; the current output port followed by a newline and a flush, under one
;; lock.
;;
;; Business Justification: the single way the service reports what it
;; does (CLAUDE.md 6.1).
;;
;; Parameters:
;;   - log: logger; the logger.
;;   - level: symbol; the severity.
;;   - msg: string; the fixed message.
;;   - detail: (or/c string? #f); the variable detail; #f by default.
;;   - trace-id: (or/c string? #f); the caller's trace identifier; #f by
;;     default.
;;   - span-id: (or/c string? #f); the caller's span identifier; #f by
;;     default.
;;
;; Returns: void.
;;
;; Errors: none (a failed write to stdout is ignored: logging must never
;; stop the service). Side Effects: writes stdout or calls the sink.
;; Complexity: O(n) in the length of the fields. Thread Safety: safe from
;; any thread. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define lines '())
;;   > (define capture (logger "digit-9" 'info (lambda (line) (set! lines (cons line lines)))))
;;   > (log-write! capture 'debug "dropped")
;;   > (log-write! capture 'info "kept" "a\"b")
;;   > (length lines)
;;   1
;;   > (regexp-match? #rx"\"msg\":\"kept\".*\"detail\":\"a\\\\\"b\"}$" (car lines))
;;   #t
;;
;; See Also: logger-format.
(define (log-write! log level msg [detail #f] [trace-id #f] [span-id #f])
  (when (>= (level-rank level) (level-rank (logger-threshold log)))
    (define line (logger-format log level msg detail trace-id span-id))
    (define sink (logger-sink log))
    (if sink
        (sink line)
        (call-with-semaphore output-lock
                             (lambda ()
                               (with-handlers ([exn:fail? void])
                                 (define out (current-output-port))
                                 (write-string line out)
                                 (newline out)
                                 (flush-output out)))))))
