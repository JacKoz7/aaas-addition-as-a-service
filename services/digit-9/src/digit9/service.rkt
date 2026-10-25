#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/service.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         The digit-9 process: configuration, start-up checks, the
;;                  HTTP server and the handling of SIGTERM, SIGINT and
;;                  SIGHUP.
;; Related Docs:    services/digit-9/README.md, CLAUDE.md 4.4 and 6.1,
;;                  ADR-0022, ADR-0031

(require "api.rkt"
         "log.rkt"
         "memory.rkt"
         "metrics.rkt"
         "server.rkt"
         "store.rkt")

(provide service-version
         (struct-out config)
         env-or
         parse-int
         load-config
         run)

;; Version of the service (SemVer, docs/CHANGELOG.md).
(define service-version "0.1.0")

;; Configuration of the service, read from the environment.
;;
;; Fields:
;;   - digit: exact-integer; the digit the service represents, 0..9
;;     (`AAAS_DIGIT`).
;;   - port: exact-integer; the HTTP port, 1..65535 (`AAAS_HTTP_PORT`).
;;   - db-path: string; the SQLite file (`AAAS_DB_PATH`).
;;   - migrations-dir: string; the directory of the migration files
;;     (`AAAS_MIGRATIONS_DIR`).
;;
;; Business Justification: no hard-coded hosts, ports or paths
;; (CLAUDE.md 6.1).
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (config-port (config 9 8080 "/data/digit-9.db" "/app/migrations"))
;;   8080
(struct config (digit port db-path migrations-dir) #:transparent)

;; An environment variable, or a fallback when it is unset or empty.
;;
;; Business Justification: configuration comes only from the environment
;; until P5.2 (CLAUDE.md 6.1).
;;
;; Parameters:
;;   - name: string; the variable name.
;;   - fallback: string; the value used when it is unset or empty.
;;
;; Returns: string; the value.
;;
;; Errors: none. Side Effects: reads the environment. Complexity: O(1).
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (env-or "AAAS_UNIT_TEST_UNSET_VARIABLE" "fallback")
;;   "fallback"
;;
;; See Also: load-config.
(define (env-or name fallback)
  (define value (getenv name))
  (if (or (not value) (string=? value "")) fallback value))

;; Parse a decimal integer within a range.
;;
;; Business Justification: invalid configuration stops the start instead
;; of being guessed at.
;;
;; Parameters:
;;   - text: string; the decimal text: 1 to 9 ASCII digits.
;;   - low: exact-integer; the smallest allowed value.
;;   - high: exact-integer; the largest allowed value.
;;
;; Returns: (or/c exact-integer? #f); the value, or #f when `text` is not
;; a plain decimal integer in `low` .. `high` (both included).
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (parse-int "8080" 1 65535)
;;   8080
;;   > (parse-int "0" 1 65535)
;;   #f
;;   > (parse-int "+8" 0 9)
;;   #f
;;   > (parse-int "1234567890" 0 9999999999)
;;   #f
;;
;; See Also: load-config.
(define (parse-int text low high)
  (and (<= 1 (string-length text) 9)
       (for/and ([c (in-string text)])
         (char<=? #\0 c #\9))
       (let ([value (string->number text)]) (and (<= low value high) value))))

;; Read the configuration from the environment.
;;
;; Description: `AAAS_BOOTSTRAP` must be env (platform arrives with P5.2);
;; `AAAS_DIGIT` must be 0..9 and `AAAS_HTTP_PORT` 1..65535. Each failure is
;; logged at error level.
;;
;; Business Justification: no hard-coded hosts, ports or paths
;; (CLAUDE.md 6.1).
;;
;; Parameters:
;;   - log: logger; the logger for the failures.
;;
;; Returns: (or/c config? #f); the configuration, or #f when a value is
;; invalid.
;;
;; Errors: none (#f). Side Effects: reads the environment; logs failures.
;; Complexity: O(1). Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (config-digit (load-config (logger "digit-9" 'error #f)))
;;   9
;;
;; See Also: run.
(define (load-config log)
  (define bootstrap (env-or "AAAS_BOOTSTRAP" "env"))
  (define digit (parse-int (env-or "AAAS_DIGIT" "9") 0 9))
  (define port (parse-int (env-or "AAAS_HTTP_PORT" "8080") 1 65535))
  (cond
    [(not (string=? bootstrap "env"))
     (log-write! log 'error "unsupported AAAS_BOOTSTRAP; only env exists before P5.2" bootstrap)
     #f]
    [(not digit)
     (log-write! log 'error "AAAS_DIGIT must be 0..9" (env-or "AAAS_DIGIT" ""))
     #f]
    [(not port)
     (log-write! log 'error "AAAS_HTTP_PORT must be 1..65535" (env-or "AAAS_HTTP_PORT" ""))
     #f]
    [else
     (config digit
             port
             (env-or "AAAS_DB_PATH" "/data/digit-9.db")
             (env-or "AAAS_MIGRATIONS_DIR" "/app/migrations"))]))

;; Open and migrate the database and check that it holds the configured
;; digit.
;;
;; Parameters:
;;   - settings: config; the configuration.
;;   - log: logger; the logger.
;;
;; Returns: (or/c store? #f); the open store, or #f when a check failed
;; (logged at error level).
;;
;; Errors: none (#f). Side Effects: opens, creates and migrates the
;; database file; logs. Complexity: O(f log f + s) in the migrations.
;; Thread Safety: call before serving.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (prepare-store (config 9 8080 "/data/digit-9.db" "/app/migrations") log)
(define (prepare-store settings log)
  (with-handlers ([exn:fail:store?
                   (lambda (error)
                     (log-write! log 'error "the database cannot be prepared" (exn-message error))
                     #f)])
    (define db (open-store (config-db-path settings) log))
    (store-migrate! db (config-migrations-dir settings))
    (cond
      [(= (digit-row-digit (store-read db)) (config-digit settings)) db]
      [else
       (log-write! log
                   'error
                   "the database does not hold the configured digit"
                   (config-db-path settings))
       (store-close! db)
       #f])))

;; The name of the signal behind a break.
;;
;; Parameters:
;;   - break: exn:break; the break raised in the main thread.
;;
;; Returns: string; `SIGTERM`, `SIGHUP` or `SIGINT`.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (signal-name (let/ec resume
;;                    (exn:break:terminate "terminate" (current-continuation-marks) resume)))
;;   "SIGTERM"
(define (signal-name break)
  (cond
    [(exn:break:terminate? break) "SIGTERM"]
    [(exn:break:hang-up? break) "SIGHUP"]
    [else "SIGINT"]))

;; Run the service.
;;
;; Description: configuration, database open and migration, digit check,
;; then the server and the memory guard until a break. Racket turns
;; SIGTERM, SIGHUP and SIGINT into breaks of the main thread; breaks are
;; disabled until the server listens, so a signal during the start is
;; handled once the server runs.
;;
;; Business Justification: the digit-9 process (CLAUDE.md 2, row 22).
;;
;; Parameters: none.
;;
;; Returns: exact-integer; the exit status: 0 after a graceful stop, 1 when
;; a start-up check fails.
;;
;; Errors: none (status 1). Side Effects: opens the database and a socket;
;; logs; serves HTTP; starts the memory guard. Complexity: runs until
;; stopped. Thread Safety: call once, on the main thread.
;; Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (exit (run))
;;
;; See Also: load-config, start-server.
(define (run)
  (break-enabled #f)
  (define log
    (logger (env-or "AAAS_SERVICE" "digit-9")
            (parse-level (env-or "AAAS_LOG_LEVEL" "info") 'info)
            #f))
  (define settings (load-config log))
  (define db (and settings (prepare-store settings log)))
  (define server
    (and
     db
     (with-handlers ([exn:fail:server?
                      (lambda (error)
                        (log-write! log
                                    'error
                                    "cannot start the HTTP server"
                                    (string-append "port "
                                                   (number->string (config-port settings))
                                                   ": "
                                                   (exn-message error)))
                        #f)])
       (start-server
        (config-port settings)
        (api db (config-digit settings) (make-metrics (config-digit settings) service-version) log)
        log))))
  (cond
    [(not server) 1]
    [else
     (start-memory-guard)
     (log-write! log
                 'info
                 "listening"
                 (string-append "port "
                                (number->string (config-port settings))
                                ", digit "
                                (number->string (config-digit settings))
                                ", version "
                                service-version))
     (define break
       (with-handlers ([exn:break? values])
         (sync/enable-break never-evt)))
     (log-write! log 'info "shutting down" (signal-name break))
     (server-stop! server)
     (store-close! db)
     (log-write! log 'info "stopped")
     0]))
