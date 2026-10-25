#lang racket/base

;; SPDX-License-Identifier: MIT
;; Copyright (c) 2026 AaaS Contributors
;;
;; Component:       digit-9
;; Module:          tools/docs.rkt
;; Owning Team:     Arithmetic Excellence Center (AEC)
;; Classification:  INTERNAL
;; Purpose:         Extraction of the doc comments of a Racket module: the
;;                  `;;` block directly above every module-level definition,
;;                  its fields (CLAUDE.md 6.5.3), its parameters and its
;;                  examples. Shared by the coverage gate, the API
;;                  documentation and the example tests.
;; Related Docs:    tools/doc-coverage.rkt, tools/api-docs.rkt,
;;                  tests/examples-test.rkt, ADR-0031

;; A doc comment is the run of lines starting with `;;` that ends on the
;; line directly above a definition. Its first line is the summary; a
;; field starts with its label and a colon (`Returns:`), several short
;; fields may share a line. Under `Parameters:` and `Fields:` each entry is
;; a line `  - name: ...`. Under `Example:` a line `  > expression` (with
;; continuation lines indented by four spaces) is evaluated by the example
;; tests and the lines up to the next `>` line are its printed result
;; (wrapped lines are joined by spaces); other lines are shown, not
;; evaluated.

(require racket/list
         racket/string)

(provide field-labels
         (struct-out item)
         (struct-out module-doc)
         read-module-doc
         item-has-label?
         item-documented-names
         item-examples
         module-purpose)

;; The labels of the doc comment fields of CLAUDE.md 6.5.3 other than the
;; summary (the first line), in the order they are written.
(define field-labels
  '("Description" "Business Justification"
                  "Parameters"
                  "Fields"
                  "Returns"
                  "Errors"
                  "Side Effects"
                  "Complexity"
                  "Thread Safety"
                  "Owner"
                  "Since"
                  "Example"
                  "See Also"))

;; One documented definition of a module.
;;
;; Fields:
;;   - kind: symbol; `procedure`, `constant`, `struct` or `submodule`.
;;   - name: symbol; the defined name (`main` for `(module+ main ...)`).
;;   - names: (listof symbol?); the parameters of a procedure in order, the
;;     fields of a struct, or empty.
;;   - provided?: boolean; #t when the module exports the name.
;;   - line: exact-positive-integer; the line of the definition.
;;   - comment: (listof string?); the doc comment without the `;; `
;;     prefixes, empty when there is none.
;;
;; Business Justification: the unit that the gate checks and the API
;; documentation shows.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (item-name (item 'constant 'max-head '() #t 1 '("Largest head.")))
;;   'max-head
(struct item (kind name names provided? line comment) #:transparent)

;; The doc comments of one module.
;;
;; Business Justification: the unit the gate and the API documentation read.
;;
;; Fields:
;;   - path: path; the source file.
;;   - header: (listof string?); the file header without the `;; `
;;     prefixes.
;;   - items: (listof item?); the module-level definitions in source order.
;;
;; Thread Safety: immutable. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (module-doc-items (module-doc (string->path "x.rkt") '() '()))
;;   '()
(struct module-doc (path header items) #:transparent)

;; Remove the comment prefix of a line.
;;
;; Parameters:
;;   - text: string; a line that starts with `;;`.
;;
;; Returns: string; the line without `;;` and one following space.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (strip-prefix ";; Returns: void.")
;;   "Returns: void."
;;   > (strip-prefix ";;")
;;   ""
(define (strip-prefix text)
  (regexp-replace #rx"^;; ?" text ""))

;; Whether a line belongs to a doc comment.
;;
;; Parameters:
;;   - text: string; a source line.
;;
;; Returns: boolean; #t for `;;` alone or followed by a space.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (comment-line? ";; text")
;;   #t
;;   > (comment-line? ";;;; section")
;;   #f
(define (comment-line? text)
  (regexp-match? #rx"^;;( |$)" text))

;; The doc comment that ends directly above a line.
;;
;; Parameters:
;;   - lines: (vectorof string?); the lines of the file.
;;   - line: exact-positive-integer; the 1-based line of a definition.
;;
;; Returns: (listof string?); the comment lines without prefixes, empty
;; when the line above is not a comment line.
;;
;; Errors: none. Side Effects: none. Complexity: O(c) in the comment
;; length. Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (comment-above (vector "" ";; Summary." ";;" ";; More." "(define x 1)") 5)
;;   '("Summary." "" "More.")
(define (comment-above lines line)
  (let collect ([index (- line 2)]
                [found '()])
    (if (and (>= index 0) (comment-line? (vector-ref lines index)))
        (collect (- index 1) (cons (strip-prefix (vector-ref lines index)) found))
        found)))

;; The names in the formals of a procedure definition.
;;
;; Description: positional and optional parameters, keyword parameters
;; (the name, not the keyword) and a rest parameter, in order.
;;
;; Parameters:
;;   - formals: any; the datum after the procedure name, for example
;;     `(a [b 1] #:c c . rest)`.
;;
;; Returns: (listof symbol?); the parameter names.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (formal-names '(a [b 1] #:c [c 2] . rest))
;;   '(a b c rest)
(define (formal-names formals)
  (let walk ([formals formals])
    (cond
      [(null? formals) '()]
      [(symbol? formals) (list formals)]
      [(keyword? (car formals)) (walk (cdr formals))]
      [(symbol? (car formals)) (cons (car formals) (walk (cdr formals)))]
      [(pair? (car formals)) (cons (caar formals) (walk (cdr formals)))]
      [else (walk (cdr formals))])))

;; The field names of a struct definition.
;;
;; Parameters:
;;   - fields: list; the field list of `struct` (after the supertype, when
;;     there is one), for example `(a [b #:mutable])`.
;;
;; Returns: (listof symbol?); the field names.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (struct-field-names '(a [b #:mutable]))
;;   '(a b)
(define (struct-field-names fields)
  (for/list ([field (in-list fields)])
    (if (pair? field)
        (car field)
        field)))

;; The names a module exports through its `provide` forms.
;;
;; Parameters:
;;   - forms: (listof any/c); the module body as data.
;;
;; Returns: (listof symbol?); the exported names; `(struct-out s)` exports
;; `s`.
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (provided-names '((provide a (struct-out b)) (define a 1)))
;;   '(a b)
(define (provided-names forms)
  (for*/list ([form (in-list forms)]
              #:when (and (pair? form) (eq? (car form) 'provide))
              [spec (in-list (cdr form))])
    (if (pair? spec)
        (cadr spec)
        spec)))

;; Classify a module-level form.
;;
;; Parameters:
;;   - form: any; the datum of the form.
;;
;; Returns: (or/c (list/c symbol? symbol? (listof symbol?)) #f); the kind,
;; the name and the parameter or field names of a definition, or #f for
;; another form (`require`, `provide`, an expression).
;;
;; Errors: none. Side Effects: none. Complexity: O(n). Thread Safety: pure.
;; Owner: Arithmetic Excellence Center (AEC). Since: digit-9 0.1.0.
;;
;; Example:
;;   > (classify '(define (f a b) a))
;;   '(procedure f (a b))
;;   > (classify '(struct s (x y) #:transparent))
;;   '(struct s (x y))
;;   > (classify '(struct exn:fail:x exn:fail ()))
;;   '(struct exn:fail:x ())
;;   > (classify '(require racket/list))
;;   #f
(define (classify form)
  (and (pair? form)
       (pair? (cdr form))
       (case (car form)
         [(define)
          (if (pair? (cadr form))
              (list 'procedure (car (cadr form)) (formal-names (cdr (cadr form))))
              (list 'constant (cadr form) '()))]
         [(struct)
          (list 'struct
                (cadr form)
                (struct-field-names (if (symbol? (caddr form))
                                        (cadddr form)
                                        (caddr form))))]
         [(module+) (list 'submodule (cadr form) '())]
         [else #f])))

;; Read the doc comments of a module.
;;
;; Description: reads the module with `read-syntax` (the `#lang` line
;; included) for the positions of its module-level forms, and the file as
;; lines for the comments.
;;
;; Business Justification: the gate, the API documentation and the example
;; tests read the same comments.
;;
;; Parameters:
;;   - path: path-string; the source file of a `#lang` module.
;;
;; Returns: module-doc; the header (the first run of comment lines) and
;; the definitions with their comments.
;;
;; Errors: raises exn:fail:read when the file is not a readable module.
;; Side Effects: reads the file. Complexity: O(n) in the file size.
;; Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   (read-module-doc "src/digit9/api.rkt")
(define (read-module-doc path)
  (define lines
    (list->vector (call-with-input-file path
                                        (lambda (in)
                                          (for/list ([text (in-lines in)])
                                            text)))))
  (define module-form
    (parameterize ([read-accept-reader #t]
                   [read-accept-lang #t])
      (call-with-input-file path
                            (lambda (in)
                              (port-count-lines! in)
                              (read-syntax path in)))))
  (define body (cdr (syntax-e (list-ref (syntax-e module-form) 3))))
  (define exported (provided-names (map syntax->datum body)))
  (module-doc (if (path? path)
                  path
                  (string->path path))
              (map strip-prefix
                   (takef (dropf (vector->list lines) (lambda (text) (not (comment-line? text))))
                          comment-line?))
              (for*/list ([form (in-list body)]
                          [described (in-value (classify (syntax->datum form)))]
                          #:when described)
                (item (first described)
                      (second described)
                      (third described)
                      (and (memq (second described) exported) #t)
                      (syntax-line form)
                      (comment-above lines (syntax-line form))))))

;; Whether a doc comment has a field.
;;
;; Description: a field label counts at the start of a line or after the
;; end of a sentence (`. `), so that short fields may share a line.
;;
;; Business Justification: the gate checks the fields of CLAUDE.md 6.5.3.
;;
;; Parameters:
;;   - documented: item; the definition.
;;   - label: string; a field label, for example "Returns".
;;
;; Returns: boolean; #t when the label and its colon appear.
;;
;; Errors: none. Side Effects: none. Complexity: O(n) in the comment.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (item-has-label? (item 'procedure 'f '() #f 1 '("F." "Errors: none. Side Effects: none."))
;;                      "Side Effects")
;;   #t
(define (item-has-label? documented label)
  (define pattern (regexp (string-append "(^|[.] )" (regexp-quote label) ":")))
  (for/or ([text (in-list (item-comment documented))])
    (regexp-match? pattern text)))

;; The names a doc comment lists under `Parameters:` or `Fields:`.
;;
;; Business Justification: the gate checks that every parameter and field is
;; described.
;;
;; Parameters:
;;   - documented: item; the definition.
;;
;; Returns: (listof symbol?); the names of the entries `  - name:` in
;; order.
;;
;; Errors: none. Side Effects: none. Complexity: O(n) in the comment.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (item-documented-names
;;      (item 'procedure 'f '(a) #f 1 '("F." "Parameters:" "  - a: string; text.")))
;;   '(a)
(define (item-documented-names documented)
  (for*/list ([text (in-list (item-comment documented))]
              [found (in-value (regexp-match #rx"^  - ([^ :]+):" text))]
              #:when found)
    (string->symbol (cadr found))))

;; The evaluated examples of a doc comment.
;;
;; Description: the lines of the `Example:` field (up to the next field
;; label at the start of a line or the end of the comment). A `  > ` line
;; starts an expression, which continues on the lines indented by four
;; spaces after it; the lines that follow, up to the next `  > ` line, are
;; its expected printed result.
;;
;; Business Justification: the examples of CLAUDE.md 6.5.3 are run as tests.
;;
;; Parameters:
;;   - documented: item; the definition.
;;
;; Returns: (listof (cons/c string? string?)); each expression (its lines
;; joined by newlines) with its expected result (the lines trimmed and
;; joined by spaces, so a long printed value may be wrapped; empty when
;; the expression prints nothing).
;;
;; Errors: none. Side Effects: none. Complexity: O(n) in the comment.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (item-examples (item 'procedure 'f '() #f 1
;;                          '("F." "Example:" "  > (f 1" "      2)" "  3" "" "Owner: x.")))
;;   '(("(f 1\n    2)" . "3"))
(define (item-examples documented)
  (define section
    (let ([after (memf (lambda (text) (string-prefix? text "Example:")) (item-comment documented))])
      (if after
          (takef (cdr after)
                 (lambda (text)
                   (not (for/or ([label (in-list field-labels)])
                          (string-prefix? text (string-append label ":"))))))
          '())))
  (let collect ([lines section]
                [examples '()])
    (cond
      [(null? lines) (reverse examples)]
      [(string-prefix? (car lines) "  > ")
       (define-values (continued after)
         (splitf-at (cdr lines) (lambda (text) (string-prefix? text "    "))))
       (define-values (result rest)
         (splitf-at after (lambda (text) (not (string-prefix? text "  > ")))))
       (collect rest
                (cons (cons (string-join (cons (substring (car lines) 4)
                                               (map (lambda (text) (substring text 2)) continued))
                                         "\n")
                            (string-join (for/list ([text (in-list result)]
                                                    #:unless (string=? (string-trim text) ""))
                                           (string-trim text))
                                         " "))
                      examples))]
      [else (collect (cdr lines) examples)])))

;; The `Purpose:` text of a file header.
;;
;; Business Justification: the API documentation opens every module with its
;; purpose.
;;
;; Parameters:
;;   - doc: module-doc; the module.
;;
;; Returns: string; the purpose, its continuation lines joined by spaces.
;;
;; Errors: none. Side Effects: none. Complexity: O(n) in the header.
;; Thread Safety: pure. Owner: Arithmetic Excellence Center (AEC).
;; Since: digit-9 0.1.0.
;;
;; Example:
;;   > (module-purpose (module-doc (string->path "x.rkt")
;;                                 '("Purpose:         Does x,"
;;                                   "                 and y."
;;                                   "Related Docs:    z")
;;                                 '()))
;;   "Does x, and y."
(define (module-purpose doc)
  (define after
    (or (memf (lambda (text) (string-prefix? text "Purpose:")) (module-doc-header doc)) '()))
  (if (null? after)
      ""
      (string-join (cons (string-trim (substring (car after) 8))
                         (for/list ([text (in-list (takef (cdr after)
                                                          (lambda (text)
                                                            (string-prefix? text "     "))))])
                           (string-trim text)))
                   " ")))
