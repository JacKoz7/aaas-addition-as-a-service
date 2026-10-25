#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          src/digit9/memory.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Memory guard of the digit-9 process: a major garbage
;;                  collection whenever the memory the runtime holds from
;;                  the system grows a fixed amount, so a burst of
;;                  connections cannot carry the process to its memory
;;                  limit.
;; Related Docs:    services/digit-9/docs/CAPACITY.md, ADR-0031

;; Racket CS (Racket on Chez Scheme) collects the young generations often,
;; but keeps the memory they free mapped for reuse; only a major
;; collection returns it to the system. It starts a major collection when
;; the heap has doubled since the previous one, and the runtime itself is
;; about 60 MiB of the heap, so after a burst the process would hold well
;; over 100 MiB until then. A major collection takes a few milliseconds
;; here, because the runtime lives in the static generation.

(require ffi/unsafe/vm)

(provide gc-headroom-bytes
         gc-interval-seconds
         held-bytes
         (struct-out memory-guard)
         start-memory-guard
         memory-guard-collections)

;; Bytes the held memory may grow above its size after the previous
;; collection before the guard collects again: 12 MiB.
(define gc-headroom-bytes (* 12 1024 1024))

;; Seconds between two checks of the held memory.
(define gc-interval-seconds 0.2)

;; The memory the runtime holds from the system, in bytes: Chez Scheme's
;; `current-memory-bytes`, the heap and its free but mapped segments.
(define held-bytes (vm-primitive 'current-memory-bytes))

;; A running memory guard.
;;
;; Fields:
;;   - thread: thread; the thread that checks the held memory.
;;   - threshold: box; the held memory, in bytes, above which the guard
;;     collects: the held memory after the previous collection plus the
;;     headroom.
;;   - count: box; the number of collections the guard has run.
;;
;; Business Justification: the service keeps answering during a flood of
;; connections instead of being stopped by its memory limit (ADR-0031).
;;
;; Thread Safety: the boxes are written by the guard's thread only.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (unbox (memory-guard-threshold (start-memory-guard))) ; about 90 MiB
(struct memory-guard (thread threshold count))

;; Start the memory guard.
;;
;; Description: runs `collect` once and sets the threshold to the held
;; memory plus `headroom`; then checks the held memory every `interval`
;; seconds and, above the threshold, runs `collect` and sets the threshold
;; again from the held memory after it. The threshold so follows the live
;; data: while many connections are open it rises, after they close it
;; falls back. The guard's thread belongs to the current custodian.
;;
;; Business Justification: bounds the memory of the process under bursts
;; of connections (CAPACITY.md) at a cost of a few milliseconds per
;; collection.
;;
;; Parameters:
;;   - headroom: exact-integer; the growth allowed, in bytes;
;;     `gc-headroom-bytes` by default (a negative value makes every check
;;     collect, for the tests).
;;   - interval: (>/c 0); seconds between checks; `gc-interval-seconds` by
;;     default.
;;   - collect: (-> any); the collection; a major `collect-garbage` by
;;     default (the tests pass a counter).
;;
;; Returns: memory-guard; the running guard.
;;
;; Errors: none. Side Effects: one collection now; starts a thread that
;; collects garbage. Complexity: O(1) per check. Thread Safety: call once
;; per process. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (define calls 0)
;;   > (define guard (start-memory-guard #:headroom -1 #:interval 0.01
;;                                       #:collect (lambda () (set! calls (add1 calls)))))
;;   > (sleep 0.1)
;;   > (positive? (memory-guard-collections guard))
;;   #t
;;   > (kill-thread (memory-guard-thread guard))
(define (start-memory-guard #:headroom [headroom gc-headroom-bytes]
                            #:interval [interval gc-interval-seconds]
                            #:collect [collect (lambda () (collect-garbage 'major))])
  (collect)
  (define threshold (box (+ (held-bytes) headroom)))
  (define count (box 0))
  (memory-guard (thread (lambda ()
                          (let check ()
                            (sleep interval)
                            (when (> (held-bytes) (unbox threshold))
                              (collect)
                              (set-box! count (add1 (unbox count)))
                              (set-box! threshold (+ (held-bytes) headroom)))
                            (check))))
                threshold
                count))

;; The number of collections a guard has run.
;;
;; Business Justification: the unit tests check that the guard collects.
;;
;; Parameters:
;;   - guard: memory-guard; the guard.
;;
;; Returns: exact-nonnegative-integer; the count.
;;
;; Errors: none. Side Effects: none. Complexity: O(1). Thread Safety: safe
;; (a read of a box). Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (memory-guard-collections (memory-guard (current-thread) (box 0) (box 3)))
;;   3
(define (memory-guard-collections guard)
  (unbox (memory-guard-count guard)))
