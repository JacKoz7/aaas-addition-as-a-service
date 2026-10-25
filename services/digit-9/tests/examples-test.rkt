#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tests/examples-test.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Runs the examples of the doc comments (CLAUDE.md 6.5.3,
;;                  Example): every `> expression` line of every module is
;;                  evaluated inside the module and its printed result
;;                  compared with the lines that follow it.
;; Related Docs:    tools/docs.rkt, ADR-0031

(require racket/path
         racket/runtime-path
         rackunit
         "../tools/docs.rkt")

;; The service directory: the modules are listed and the examples run from
;; here, so relative paths in examples resolve as in the image.
(define-runtime-path service-dir "..")

;; The modules whose examples are run: the sources, the tools and the test
;; fixtures.
(define module-files
  (for*/list ([dir (in-list '("src/digit9" "tools" "tests"))]
              [name (in-list (sort (map path->string (directory-list (build-path service-dir dir)))
                                   string<?))]
              #:when (regexp-match? #rx"[.]rkt$" name)
              #:unless (regexp-match? #rx"-test[.]rkt$" name))
    (simplify-path (build-path service-dir dir name))))

;; The printed form of the values of an expression.
;;
;; Parameters:
;;   - results: list; the values the expression returned.
;;
;; Returns: string; each value as `print` writes it, separated by spaces;
;; void values print nothing.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (printed (list "a" 'b (void) 3))
;;   "\"a\" 'b 3"
(define (printed results)
  (define out (open-output-string))
  (for ([value (in-list results)]
        #:unless (void? value))
    (unless (zero? (file-position out))
      (write-char #\space out))
    (parameterize ([print-as-expression #t])
      (print value out)))
  (get-output-string out))

;; The examples of all modules, evaluated in each module's namespace.
(parameterize ([current-directory service-dir]
               [current-namespace (make-base-namespace)])
  (define evaluated
    (for/sum
     ([file (in-list module-files)])
     (define module-path `(file ,(path->string file)))
     (dynamic-require module-path #f)
     (define namespace (module->namespace module-path))
     (for*/sum
      ([documented (in-list (module-doc-items (read-module-doc file)))]
       [example (in-list (item-examples documented))])
      (define expression (car example))
      (define label
        (format "~a: ~a: ~a" (file-name-from-path file) (item-name documented) expression))
      (define actual
        (with-handlers ([exn:fail? (lambda (error) (string-append "raised: " (exn-message error)))])
          (printed (call-with-values (lambda ()
                                       (eval (read (open-input-string expression)) namespace))
                                     list))))
      (check-equal? actual (cdr example) label)
      1)))
  (test-case "every module has evaluated examples"
    (check-true (> evaluated 100) (format "~a examples evaluated" evaluated))))
