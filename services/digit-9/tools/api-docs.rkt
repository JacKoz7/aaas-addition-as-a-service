#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tools/api-docs.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         API documentation of the digit-9 service: builds a
;;                  Scribble document from the doc comments of the modules
;;                  and renders it as HTML (CLAUDE.md 6.5.3, Scribble).
;; Related Docs:    tools/docs.rkt, ADR-0010, ADR-0031

;; Usage: racket tools/api-docs.rkt <output-directory> <file.rkt> ...
;; Writes index.html and Scribble's style files into the directory.

(require racket/list
         racket/string
         (except-in scribble/base item item?)
         scribble/decode
         (prefix-in html: scribble/html-render)
         scribble/render
         "docs.rkt")

(provide comment-blocks
         item-signature
         module-section
         render-api-docs)

;; Split a doc comment into blocks for rendering.
;;
;; Description: blank lines separate paragraphs; inside a paragraph, a run
;; of lines indented by two spaces (parameter entries, examples) becomes a
;; verbatim block and the other lines become prose joined by spaces.
;;
;; Business Justification: keeps the line structure of parameter lists and
;; examples in the HTML.
;;
;; Parameters:
;;   - lines: (listof string?); the comment lines without prefixes.
;;
;; Returns: (listof (cons/c (or/c 'prose 'verbatim) string?)); the blocks
;; in order.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (comment-blocks '("Summary." "" "Parameters:" "  - a: x." "  - b: y."))
;;   '((prose . "Summary.") (prose . "Parameters:") (verbatim . "- a: x.\n- b: y."))
(define (comment-blocks lines)
  (let collect ([lines lines]
                [blocks '()])
    (cond
      [(null? lines) (reverse blocks)]
      [(string=? (string-trim (car lines)) "") (collect (cdr lines) blocks)]
      [(string-prefix? (car lines) "  ")
       (define-values (run rest) (splitf-at lines (lambda (text) (string-prefix? text "  "))))
       (collect rest
                (cons (cons 'verbatim
                            (string-join (map (lambda (text) (substring text 2)) run) "\n"))
                      blocks))]
      [else
       (define-values (run rest)
         (splitf-at lines
                    (lambda (text)
                      (not (or (string-prefix? text "  ") (string=? (string-trim text) ""))))))
       (collect rest (cons (cons 'prose (string-join (map string-trim run) " ")) blocks))])))

;; The signature line of a definition.
;;
;; Business Justification: every definition is shown with its parameters or
;; fields.
;;
;; Parameters:
;;   - documented: item; the definition.
;;
;; Returns: string; `(name parameter ...)` for a procedure,
;; `(struct name (field ...))` for a struct, the name otherwise.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (item-signature (item 'procedure 'f '(a b) #t 1 '()))
;;   "(f a b)"
;;   > (item-signature (item 'struct 's '(x) #t 1 '()))
;;   "(struct s (x))"
(define (item-signature documented)
  (define name (symbol->string (item-name documented)))
  (define names (map symbol->string (item-names documented)))
  (case (item-kind documented)
    [(procedure) (string-append "(" (string-join (cons name names)) ")")]
    [(struct) (string-append "(struct " name " (" (string-join names) "))")]
    [(submodule) (string-append "(module+ " name " ...)")]
    [else name]))

;; The Scribble content of one module: its purpose and every definition
;; with its signature and doc comment.
;;
;; Business Justification: one section per module in the portal (ADR-0010).
;;
;; Parameters:
;;   - doc: module-doc; the module.
;;   - name: string; the module path shown as the section title.
;;
;; Returns: list; the section start and the content, for `decode`.
;;
;; Errors: none. Side Effects: none. Complexity: O(n) in the comments.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (length (module-section (module-doc (string->path "x.rkt") '("Purpose:         X.") '())
;;                             "x.rkt"))
;;   2
(define (module-section doc name)
  (append
   (list (section (tt name)) (para (module-purpose doc)))
   (append-map
    (lambda (documented)
      (append (list (subsection (tt (symbol->string (item-name documented))))
                    (para (tt (item-signature documented))
                          (string-append " — "
                                         (if (item-provided? documented) "exported" "private")
                                         " "
                                         (symbol->string (item-kind documented)))))
              (for/list ([block (in-list (comment-blocks (item-comment documented)))])
                (if (eq? (car block) 'verbatim)
                    (verbatim (cdr block))
                    (para (cdr block))))))
    (module-doc-items doc))))

;; Render the API documentation of modules as HTML.
;;
;; Business Justification: the native API documentation of the service in
;; the portal (CLAUDE.md 6.5.7).
;;
;; Parameters:
;;   - dest: path-string; the output directory (created when missing).
;;   - files: (listof path-string?); the modules, in the order shown.
;;
;; Returns: void.
;;
;; Errors: raises exn:fail:read for a file that is not a module and
;; exn:fail:filesystem when the directory cannot be written.
;; Side Effects: writes index.html and the style files into `dest`.
;; Complexity: O(n) in the sources. Thread Safety: safe.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   (render-api-docs "/api-docs" '("src/digit9/api.rkt"))
(define (render-api-docs dest files)
  (make-directory* dest)
  (define document
    (decode (append (list (title "digit-9 API")
                          (para "Reference of the digit-9 service (Racket), generated from the "
                                "doc comments of its modules. Private definitions are included."))
                    (append-map (lambda (file) (module-section (read-module-doc file) file))
                                files))))
  (render (list document) (list "index") #:dest-dir dest #:render-mixin html:render-mixin))

;; Create a directory and its missing parents.
;;
;; Parameters:
;;   - dir: path-string; the directory.
;;
;; Returns: void.
;;
;; Errors: raises exn:fail:filesystem when a directory cannot be created.
;; Side Effects: creates directories. Complexity: O(d) in the depth.
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (make-directory* "/api-docs")
(define (make-directory* dir)
  (define-values (parent _name _directory?) (split-path (path->complete-path dir)))
  (unless (directory-exists? dir)
    (when (path? parent)
      (make-directory* parent))
    (make-directory dir)))

;; The command line: renders the files named after the output directory.
(module+ main
  (define arguments (vector->list (current-command-line-arguments)))
  (render-api-docs (first arguments) (rest arguments)))
