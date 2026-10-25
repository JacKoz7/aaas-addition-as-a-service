#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/sqlite.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Bindings to the SQLite C library through the Racket
;;                  foreign function interface: the few functions the store
;;                  needs to open, migrate and read the digit database.
;; Related Docs:    src/digit9/store.rkt, https://sqlite.org/c3ref/intro.html,
;;                  ADR-0031

;; The `db` library of Racket is not used: it loads the contract and class
;; systems, which more than double the resident memory of the process
;; (ADR-0031). Every call blocks the Racket virtual machine for its
;; duration; the statements of the service touch one row.

(require ffi/unsafe)

(provide sqlite-ok
         sqlite-row
         sqlite-done
         sqlite-open-readwrite
         sqlite-open-create
         sqlite3-open-v2
         sqlite3-close
         sqlite3-errmsg
         sqlite3-exec
         sqlite3-prepare-v2
         sqlite3-bind-text
         sqlite3-step
         sqlite3-column-int
         sqlite3-finalize
         sqlite3-busy-timeout
         sqlite3-get-autocommit)

;; The shared SQLite library (`libsqlite3.so.0`, Alpine package
;; `sqlite-libs`); loading fails the start when it is missing.
(define libsqlite3 (ffi-lib "libsqlite3" '("0" #f)))

;; Result code SQLITE_OK: the call succeeded.
(define sqlite-ok 0)

;; Result code SQLITE_ROW: `sqlite3_step` has a row ready.
(define sqlite-row 100)

;; Result code SQLITE_DONE: `sqlite3_step` finished the statement.
(define sqlite-done 101)

;; Open flag SQLITE_OPEN_READWRITE.
(define sqlite-open-readwrite #x00000002)

;; Open flag SQLITE_OPEN_CREATE: create the file when it is missing.
(define sqlite-open-create #x00000004)

;; The destructor value SQLITE_TRANSIENT (-1): SQLite copies a bound text
;; before the call returns.
(define sqlite-transient -1)

;; `sqlite3_open_v2(filename, &db, flags, vfs)`: open a database; returns
;; two values, the result code and the connection pointer (set even on
;; failure, unless out of memory).
(define sqlite3-open-v2
  (get-ffi-obj "sqlite3_open_v2"
               libsqlite3
               (_fun _string/utf-8
                     (handle : (_ptr o _pointer))
                     _int
                     (_pointer = #f)
                     ->
                     (status : _int)
                     ->
                     (values status handle))))

;; `sqlite3_close(db)`: close a connection; returns the result code.
(define sqlite3-close (get-ffi-obj "sqlite3_close" libsqlite3 (_fun _pointer -> _int)))

;; `sqlite3_errmsg(db)`: the English message of the last error of a
;; connection, as a string.
(define sqlite3-errmsg (get-ffi-obj "sqlite3_errmsg" libsqlite3 (_fun _pointer -> _string/utf-8)))

;; `sqlite3_free(pointer)`: release memory SQLite allocated (the error
;; message of `sqlite3_exec`).
(define sqlite3-free (get-ffi-obj "sqlite3_free" libsqlite3 (_fun _pointer -> _void)))

;; `sqlite3_exec(db, sql, NULL, NULL, &error)` without a callback: run SQL
;; statements; returns two values, the result code and the error message
;; pointer SQLite allocated (#f when none).
(define sqlite3-exec-raw
  (get-ffi-obj "sqlite3_exec"
               libsqlite3
               (_fun _pointer
                     _string/utf-8
                     (_pointer = #f)
                     (_pointer = #f)
                     (error : (_ptr o _pointer))
                     ->
                     (status : _int)
                     ->
                     (values status error))))

;; Run SQL statements without results (`sqlite3_exec`).
;;
;; Business Justification: the migrations and the transaction control of
;; the store run through it.
;;
;; Parameters:
;;   - handle: cpointer; an open connection.
;;   - sql: string; one or more SQL statements.
;;
;; Returns: two values: exact-integer, the result code; (or/c string? #f),
;; the error message, or #f when none.
;;
;; Errors: none (the result code). Side Effects: whatever the SQL does;
;; frees the SQLite copy of the message. Complexity: that of the
;; statements. Thread Safety: as the connection.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (sqlite3-exec handle "BEGIN IMMEDIATE;") ; 0 and #f on success
(define (sqlite3-exec handle sql)
  (define-values (status error) (sqlite3-exec-raw handle sql))
  (values status (take-message error)))

;; `sqlite3_prepare_v2(db, sql, -1, &statement, NULL)`: compile one
;; statement; returns two values, the result code and the statement
;; pointer (#f on failure).
(define sqlite3-prepare-v2
  (get-ffi-obj "sqlite3_prepare_v2"
               libsqlite3
               (_fun _pointer
                     _string/utf-8
                     (_int = -1)
                     (statement : (_ptr o _pointer))
                     (_pointer = #f)
                     ->
                     (status : _int)
                     ->
                     (values status statement))))

;; `sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)`: bind
;; a text parameter (1-based index); returns the result code.
(define sqlite3-bind-text
  (get-ffi-obj "sqlite3_bind_text"
               libsqlite3
               (_fun _pointer _int _string/utf-8 (_int = -1) (_intptr = sqlite-transient) -> _int)))

;; `sqlite3_step(statement)`: run a statement to its next row; returns the
;; result code (SQLITE_ROW, SQLITE_DONE or an error).
(define sqlite3-step (get-ffi-obj "sqlite3_step" libsqlite3 (_fun _pointer -> _int)))

;; `sqlite3_column_int(statement, index)`: the integer in a column of the
;; current row (0-based index).
(define sqlite3-column-int
  (get-ffi-obj "sqlite3_column_int" libsqlite3 (_fun _pointer _int -> _int)))

;; `sqlite3_finalize(statement)`: release a statement; a NULL statement
;; (#f) is a no-op.
(define sqlite3-finalize (get-ffi-obj "sqlite3_finalize" libsqlite3 (_fun _pointer -> _int)))

;; `sqlite3_busy_timeout(db, milliseconds)`: how long a call waits for a
;; lock held by another connection.
(define sqlite3-busy-timeout
  (get-ffi-obj "sqlite3_busy_timeout" libsqlite3 (_fun _pointer _int -> _int)))

;; `sqlite3_get_autocommit(db)`: 0 while a transaction is open, non-zero
;; otherwise.
(define sqlite3-get-autocommit
  (get-ffi-obj "sqlite3_get_autocommit" libsqlite3 (_fun _pointer -> _int)))

;; Copy an error message SQLite allocated and release the original.
;;
;; Parameters:
;;   - pointer: (or/c cpointer? #f); a NUL-terminated message SQLite
;;     allocated, or #f.
;;
;; Returns: (or/c string? #f); the message, or #f when `pointer` is #f.
;;
;; Errors: none. Side Effects: frees the SQLite memory. Complexity: O(n).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (take-message #f)
;;   #f
(define (take-message pointer)
  (and pointer
       (let ([message (cast pointer _pointer _string/utf-8)])
         (sqlite3-free pointer)
         message)))
