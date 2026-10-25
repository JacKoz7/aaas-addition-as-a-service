#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/store.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         SQLite storage of the digit: opening the database,
;;                  applying the versioned migrations and reading the row
;;                  that holds the value and successor of the digit.
;; Related Docs:    services/digit-9/README.md, migrations/0001_digit.sql,
;;                  CLAUDE.md 4.4, ADR-0022, ADR-0031

(require racket/list
         racket/string
         "log.rkt"
         "sqlite.rkt")

(provide (struct-out exn:fail:store)
         (struct-out digit-row)
         (struct-out store)
         open-store
         store-close!
         store-execute!
         store-applied?
         store-migrate!
         store-read)

;; Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1).
(define busy-timeout-ms 2000)

;; Bookkeeping table of the migration runner: one row per applied file;
;; `version` is the file name, `applied_at` the UTC time (ISO 8601).
(define migrations-table
  (string-append "CREATE TABLE IF NOT EXISTS schema_migrations ("
                 " version TEXT PRIMARY KEY NOT NULL, applied_at TEXT NOT NULL) STRICT;"))

;; A storage failure: the database cannot be opened, migrated or read.
;;
;; Fields: those of exn:fail (message and continuation marks); the message
;; says what failed, with the SQLite message when there is one.
;;
;; Business Justification: callers handle one error type, whatever SQLite
;; or the file system reported.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (exn-message (exn:fail:store "cannot open" (current-continuation-marks)))
;;   "cannot open"
(struct exn:fail:store exn:fail ())

;; The digit row of the database (table `digit` of 0001_digit.sql).
;;
;; Fields:
;;   - digit: exact-integer; the digit the service represents, 0..9.
;;   - value: exact-integer; the numeric value of the digit, 0..9.
;;   - next: exact-integer; the successor of the digit in base 10, 0..9.
;;   - carry: boolean; #t when the successor wraps to 0 (digit 9 only).
;;
;; Business Justification: the arithmetic facts of the digit, read on
;; every request (CLAUDE.md 4.4).
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (digit-row-carry (digit-row 9 9 0 #t))
;;   #t
(struct digit-row (digit value next carry) #:transparent)

;; The SQLite database of the service (one connection).
;;
;; Fields:
;;   - handle: (or/c cpointer? #f); the open connection, #f after
;;     `store-close!` (mutable).
;;   - log: logger; the logger of the migration runner.
;;
;; Business Justification: each service owns its database (CLAUDE.md 1,
;; rule 4).
;;
;; Thread Safety: not synchronised; used before the server starts and then
;; only through the contract, which the server calls under one lock
;; (ADR-0031). Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (store? (open-store ":memory:" (logger "digit-9" 'error #f)))
;;   #t
(struct store ([handle #:mutable] log))

;; Raise a storage failure.
;;
;; Parameters:
;;   - message: string; what failed.
;;
;; Returns: never returns.
;;
;; Errors: always raises exn:fail:store with `message`. Side Effects: none.
;; Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (with-handlers ([exn:fail:store? exn-message]) (store-fail "boom"))
;;   "boom"
(define (store-fail message)
  (raise (exn:fail:store message (current-continuation-marks))))

;; Open (or create) the SQLite database file.
;;
;; Description: opens `path` read-write, creating it when missing, sets a
;; busy timeout of 2 s and enables foreign keys.
;;
;; Business Justification: the database of the service lives in its own
;; volume (`digit-9-data`).
;;
;; Parameters:
;;   - path: string; the database file, or `:memory:` for an in-memory
;;     database.
;;   - log: logger; the logger of the migration runner.
;;
;; Returns: store; the open database.
;;
;; Errors: raises exn:fail:store when SQLite cannot open the file.
;; Side Effects: creates the file when missing. Complexity: O(1).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (store-handle (open-store ":memory:" (logger "digit-9" 'error #f)))
;;   #<cpointer>
;;
;; See Also: store-migrate!.
(define (open-store path log)
  (define-values (status handle)
    (sqlite3-open-v2 path (bitwise-ior sqlite-open-readwrite sqlite-open-create)))
  (unless (= status sqlite-ok)
    (define message
      (if handle
          (sqlite3-errmsg handle)
          "out of memory"))
    (when handle
      (sqlite3-close handle))
    (store-fail (string-append "cannot open the database: " message)))
  (sqlite3-busy-timeout handle busy-timeout-ms)
  (define opened (store handle log))
  (store-execute! opened "PRAGMA foreign_keys = ON;")
  opened)

;; Close the connection; later calls are no-ops.
;;
;; Business Justification: the connection is released on a graceful stop and
;; after a failed start-up check.
;;
;; Parameters:
;;   - db: store; the database.
;;
;; Returns: void.
;;
;; Errors: none. Side Effects: closes the connection. Complexity: O(1).
;; Thread Safety: call when no request uses the store.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define closing (open-store ":memory:" (logger "digit-9" 'error #f)))
;;   > (store-close! closing)
;;   > (store-handle closing)
;;   #f
(define (store-close! db)
  (define handle (store-handle db))
  (when handle
    (sqlite3-close handle)
    (set-store-handle! db #f)))

;; The open connection of a store, or a failure after `store-close!`.
;;
;; Parameters:
;;   - db: store; the database.
;;
;; Returns: cpointer; the connection.
;;
;; Errors: raises exn:fail:store when the store is closed. Side Effects:
;; none. Complexity: O(1). Thread Safety: as the store.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (open-handle (open-store ":memory:" (logger "digit-9" 'error #f)))
;;   #<cpointer>
(define (open-handle db)
  (or (store-handle db) (store-fail "the database is closed")))

;; Execute one or more SQL statements without results.
;;
;; Description: used by the migration runner and by the unit tests.
;;
;; Business Justification: one place where SQL errors become
;; exn:fail:store.
;;
;; Parameters:
;;   - db: store; the database.
;;   - sql: string; the SQL text.
;;
;; Returns: void.
;;
;; Errors: raises exn:fail:store with the SQLite message when a statement
;; fails. Side Effects: whatever the SQL does. Complexity: that of the
;; statements. Thread Safety: as the store.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define scratch (open-store ":memory:" (logger "digit-9" 'error #f)))
;;   > (store-execute! scratch "CREATE TABLE t (x INTEGER);")
;;   > (with-handlers ([exn:fail:store? exn-message]) (store-execute! scratch "SELEC 1;"))
;;   "near \"SELEC\": syntax error"
(define (store-execute! db sql)
  (define-values (status message) (sqlite3-exec (open-handle db) sql))
  (unless (= status sqlite-ok)
    (store-fail (or message (sqlite3-errmsg (open-handle db))))))

;; Run a procedure with a prepared statement and finalise it afterwards.
;;
;; Parameters:
;;   - db: store; the database.
;;   - sql: string; one SQL statement.
;;   - use: (-> cpointer? any); receives the statement.
;;
;; Returns: any; the results of `use`.
;;
;; Errors: raises exn:fail:store when the statement cannot be prepared;
;; whatever `use` raises. Side Effects: those of `use`. Complexity: that of
;; `use`. Thread Safety: as the store.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (call-with-statement (open-store ":memory:" (logger "digit-9" 'error #f))
;;                          "SELECT 7;"
;;                          (lambda (statement)
;;                            (sqlite3-step statement)
;;                            (sqlite3-column-int statement 0)))
;;   7
(define (call-with-statement db sql use)
  (define handle (open-handle db))
  (define-values (status statement) (sqlite3-prepare-v2 handle sql))
  (unless (= status sqlite-ok)
    (sqlite3-finalize statement)
    (store-fail (sqlite3-errmsg handle)))
  (dynamic-wind void (lambda () (use statement)) (lambda () (sqlite3-finalize statement))))

;; Whether a migration is recorded in `schema_migrations`.
;;
;; Description: a failing query counts as "not applied", so that the
;; following apply fails loudly instead of skipping silently.
;;
;; Business Justification: each migration runs exactly once.
;;
;; Parameters:
;;   - db: store; the database.
;;   - version: string; the migration file name.
;;
;; Returns: boolean; #t when recorded.
;;
;; Errors: none. Side Effects: one SELECT. Complexity: O(log m) in the
;; recorded migrations. Thread Safety: as the store.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (store-applied? (open-store ":memory:" (logger "digit-9" 'error #f)) "0001_digit.sql")
;;   #f
(define (store-applied? db version)
  (with-handlers ([exn:fail:store? (lambda (_) #f)])
    (call-with-statement db
                         "SELECT 1 FROM schema_migrations WHERE version = ?1;"
                         (lambda (statement)
                           (sqlite3-bind-text statement 1 version)
                           (= (sqlite3-step statement) sqlite-row)))))

;; Read a whole text file.
;;
;; Parameters:
;;   - path: path-string; the file.
;;
;; Returns: string; its content, decoded as UTF-8.
;;
;; Errors: raises exn:fail:filesystem when the file cannot be read.
;; Side Effects: reads the file. Complexity: O(s) in its size.
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (string? (read-text (collection-file-path "base.rkt" "racket")))
;;   #t
(define (read-text path)
  (call-with-input-file path
                        (lambda (in)
                          (define content (read-bytes (max 1 (file-size path)) in))
                          (if (eof-object? content)
                              ""
                              (bytes->string/utf-8 content #\uFFFD)))))

;; Apply one migration file and record it, in one transaction.
;;
;; Description: on any failure the transaction is rolled back.
;;
;; Business Justification: a half-applied migration must never be
;; recorded as applied.
;;
;; Parameters:
;;   - db: store; the database.
;;   - dir: path-string; the migrations directory.
;;   - version: string; the migration file name inside `dir`.
;;
;; Returns: void.
;;
;; Errors: raises exn:fail:store when the file cannot be read or its SQL or
;; the record fails. Side Effects: writes the database; logs the applied
;; file. Complexity: O(s) in the file size. Thread Safety: as the store.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (store-apply! db "/app/migrations" "0001_digit.sql")
(define (store-apply! db dir version)
  (define sql
    (with-handlers ([exn:fail:filesystem?
                     (lambda (_) (store-fail (string-append "cannot read migration " version)))])
      (read-text (build-path dir version))))
  (with-handlers ([exn:fail:store?
                   (lambda (error)
                     (when (zero? (sqlite3-get-autocommit (open-handle db)))
                       (sqlite3-exec (open-handle db) "ROLLBACK;"))
                     (store-fail
                      (string-append "migration " version " failed: " (exn-message error))))])
    (store-execute! db "BEGIN IMMEDIATE;")
    (store-execute! db sql)
    (call-with-statement db
                         (string-append "INSERT INTO schema_migrations (version, applied_at) "
                                        "VALUES (?1, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));")
                         (lambda (statement)
                           (sqlite3-bind-text statement 1 version)
                           (unless (= (sqlite3-step statement) sqlite-done)
                             (store-fail (sqlite3-errmsg (open-handle db))))))
    (store-execute! db "COMMIT;"))
  (log-write! (store-log db) 'info "migration applied" version))

;; The migration files of a directory, in the order they are applied.
;;
;; Description: the regular files whose names end with `.sql` and do not
;; start with a dot, sorted lexically.
;;
;; Parameters:
;;   - dir: path-string; the directory.
;;
;; Returns: (listof string?); the file names.
;;
;; Errors: raises exn:fail:store when the directory cannot be read.
;; Side Effects: reads the directory. Complexity: O(f log f).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (with-handlers ([exn:fail:store? exn-message]) (migration-files "/nonexistent"))
;;   "cannot read the migrations directory /nonexistent"
(define (migration-files dir)
  (define names
    (with-handlers ([exn:fail:filesystem?
                     (lambda (_)
                       (store-fail (string-append "cannot read the migrations directory "
                                                  (if (path? dir)
                                                      (path->string dir)
                                                      dir))))])
      (for/list ([entry (in-list (directory-list dir))]
                 #:when (file-exists? (build-path dir entry)))
        (path->string entry))))
  (sort (filter (lambda (name) (and (not (string-prefix? name ".")) (string-suffix? name ".sql")))
                names)
        string<?))

;; Apply the migrations of a directory that are not applied yet.
;;
;; Description: creates `schema_migrations` when missing, then applies each
;; file of `migration-files` not recorded yet, in one transaction per file
;; with its record. Running it again applies nothing.
;;
;; Business Justification: migrations run at start-up and are versioned
;; (CLAUDE.md 6.1); the seed of the digit is a migration, so the digit
;; lives in the database, not the code.
;;
;; Parameters:
;;   - db: store; the database.
;;   - dir: path-string; the directory with the migration files.
;;
;; Returns: exact-nonnegative-integer; the number of files applied by this
;; call.
;;
;; Errors: raises exn:fail:store when the directory or a file cannot be
;; read or its SQL fails. Side Effects: reads files; writes the database;
;; logs each applied file. Complexity: O(f log f + s). Thread Safety: call
;; before serving. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (store-migrate! db "/app/migrations") ; 1 on a new volume, then 0
;;
;; See Also: store-read.
(define (store-migrate! db dir)
  (store-execute! db migrations-table)
  (count (lambda (name)
           (and (not (store-applied? db name))
                (begin
                  (store-apply! db dir name)
                  #t)))
         (migration-files dir)))

;; Read the digit row.
;;
;; Description: requires the table `digit` to hold exactly one row; zero
;; rows or more than one are an error, as is any SQLite failure.
;;
;; Business Justification: GET /value, GET /next and GET /health answer
;; from this read on every request (CLAUDE.md 4.4).
;;
;; Parameters:
;;   - db: store; the database.
;;
;; Returns: digit-row; the row.
;;
;; Errors: raises exn:fail:store when the query fails or the table does not
;; hold exactly one row. Side Effects: one SELECT. Complexity: O(1).
;; Thread Safety: as the store. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (with-handlers ([exn:fail:store? exn-message])
;;       (store-read (open-store ":memory:" (logger "digit-9" 'error #f))))
;;   "no such table: digit"
;;
;; See Also: digit-row.
(define (store-read db)
  (call-with-statement
   db
   "SELECT digit, value, next, carry FROM digit LIMIT 2;"
   (lambda (statement)
     (define status (sqlite3-step statement))
     (cond
       [(= status sqlite-done) (store-fail "the table digit holds no row")]
       [(not (= status sqlite-row)) (store-fail (sqlite3-errmsg (open-handle db)))]
       [else (void)])
     (define row
       (digit-row (sqlite3-column-int statement 0)
                  (sqlite3-column-int statement 1)
                  (sqlite3-column-int statement 2)
                  (not (zero? (sqlite3-column-int statement 3)))))
     (unless (= (sqlite3-step statement) sqlite-done)
       (store-fail "the table digit holds more than one row"))
     row)))
