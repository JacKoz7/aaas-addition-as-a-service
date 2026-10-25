#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tools/doc-coverage.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Documentation coverage gate of the digit-9 service: every
;;                  module-level definition, private ones included, must
;;                  carry a doc comment with the fields of CLAUDE.md 6.5.3
;;                  (CLAUDE.md 6.5.4: 100%).
;; Related Docs:    tools/docs.rkt, CLAUDE.md 6.5.3 and 6.5.4, ADR-0031

;; Usage: racket tools/doc-coverage.rkt <file.rkt> ...
;; Prints every finding and a summary; exits with status 1 on any finding.

(require racket/list
         racket/string
         "docs.rkt")

(provide item-findings
         module-findings
         main)

;; The fields every procedure documents, besides its summary.
(define procedure-labels
  '("Parameters" "Returns"
                 "Errors"
                 "Side Effects"
                 "Complexity"
                 "Thread Safety"
                 "Owner"
                 "Since"
                 "Example"))

;; The fields every struct documents, besides its summary.
(define struct-labels '("Fields" "Thread Safety" "Owner" "Since" "Example"))

;; The findings for one definition.
;;
;; Description: every definition needs a doc comment whose first line is
;; a summary. Procedures need the fields of `procedure-labels` and structs
;; those of `struct-labels`; exported procedures and structs also need
;; `Business Justification`. The `Parameters:` (or `Fields:`) entries must
;; name exactly the parameters (or fields), in order. Constants and
;; submodules need the summary only.
;;
;; Business Justification: CLAUDE.md 6.5.4 requires 100% documentation
;; coverage, private definitions included, and no Racket tool checks it.
;;
;; Parameters:
;;   - documented: item; the definition.
;;
;; Returns: (listof string?); the findings, empty when it is documented.
;;
;; Errors: none. Side Effects: none. Complexity: O(n) in the comment.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (item-findings (item 'constant 'x '() #f 3 '()))
;;   '("x: no doc comment")
;;   > (item-findings (item 'procedure 'f '(a) #f 3 '("F." "Parameters:" "  - b: x.")))
;;   '("f: no Returns field"
;;     "f: no Errors field"
;;     "f: no Side Effects field"
;;     "f: no Complexity field"
;;     "f: no Thread Safety field"
;;     "f: no Owner field"
;;     "f: no Since field"
;;     "f: no Example field"
;;     "f: documents (b), but the parameters are (a)")
(define (item-findings documented)
  (define name (symbol->string (item-name documented)))
  (define comment (item-comment documented))
  (define kind (item-kind documented))
  (define required
    (append (case kind
              [(procedure) procedure-labels]
              [(struct) struct-labels]
              [else '()])
            (if (and (item-provided? documented) (memq kind '(procedure struct)))
                '("Business Justification")
                '())))
  (cond
    [(null? comment) (list (string-append name ": no doc comment"))]
    [(or (string=? (string-trim (car comment)) "")
         (for/or ([label (in-list field-labels)])
           (string-prefix? (car comment) (string-append label ":"))))
     (list (string-append name ": the first line is not a summary"))]
    [else
     (append (for/list ([label (in-list required)]
                        #:unless (item-has-label? documented label))
               (string-append name ": no " label " field"))
             (if (and (memq kind '(procedure struct))
                      (not (equal? (item-documented-names documented) (item-names documented))))
                 (list (string-append name
                                      ": documents ("
                                      (string-join (map symbol->string
                                                        (item-documented-names documented)))
                                      "), but the "
                                      (if (eq? kind 'struct) "fields" "parameters")
                                      " are ("
                                      (string-join (map symbol->string (item-names documented)))
                                      ")"))
                 '()))]))

;; The findings for one module.
;;
;; Business Justification: findings name the file and the line to fix.
;;
;; Parameters:
;;   - doc: module-doc; the module.
;;
;; Returns: (listof string?); the findings, each prefixed with the file
;; and the line; a header without `Purpose:` is one finding.
;;
;; Errors: none. Side Effects: none. Complexity: O(n) in the module.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (module-findings (module-doc (string->path "x.rkt")
;;                                  '("Purpose:         X.")
;;                                  (list (item 'constant 'y '() #f 4 '("Y.")))))
;;   '()
(define (module-findings doc)
  (define file (path->string (module-doc-path doc)))
  (append (if (string=? (module-purpose doc) "")
              (list (string-append file ": the file header has no Purpose"))
              '())
          (for*/list ([documented (in-list (module-doc-items doc))]
                      [finding (in-list (item-findings documented))])
            (string-append file ":" (number->string (item-line documented)) ": " finding))))

;; Check the files named on the command line.
;;
;; Business Justification: the doc-coverage stage of the image fails on any
;; finding (CLAUDE.md 6.5.4).
;;
;; Parameters:
;;   - files: (listof path-string?); the modules to check.
;;
;; Returns: exact-integer; 0 when every definition is documented, 1
;; otherwise or when no file is given.
;;
;; Errors: raises exn:fail:read for a file that is not a module.
;; Side Effects: reads the files; prints the findings and a summary to
;; stdout. Complexity: O(n) in the sources. Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (main '("src/digit9/api.rkt" "src/digit9/http.rkt")) ; 0 when complete
(define (main files)
  (define docs (map read-module-doc files))
  (define findings (append-map module-findings docs))
  (define total (for/sum ([doc (in-list docs)]) (length (module-doc-items doc))))
  (for ([finding (in-list findings)])
    (displayln finding))
  (define undocumented
    (length (remove-duplicates (map (lambda (text) (car (string-split text ": "))) findings))))
  (printf "doc-coverage: ~a/~a definitions documented in ~a files\n"
          (- total (min total undocumented))
          total
          (length docs))
  (if (and (null? findings) (pair? files)) 0 1))

;; The command line: checks the given files and exits with the status of
;; `main`.
(module+ main
  (exit (main (vector->list (current-command-line-arguments)))))
