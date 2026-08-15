(in-package #:cl-tui-kit/tests)

;;;; Coverage for the CL-TUI-KIT-ERROR hierarchy in src/conditions.lisp, which
;;;; replaced ~79 SIMPLE-ERROR call sites.  Every test here signals through a
;;;; real call site rather than constructing a condition instance directly, so
;;;; a regression that changes what a site signals is what makes these fail.

(deftest condition-hierarchy-distinguishes-invalid-geometry
    (:conditions)
  ;; %COORDINATE (src/geometry.lisp:6-9) signals INVALID-TYPE-ERROR, which
  ;; also inherits CL:TYPE-ERROR -- the type the geometry constructors
  ;; signalled before this hierarchy existed.
  (let ((condition
          (handler-case (progn (make-point 1.5 0) nil)
            (error (c) c))))
    (is (typep condition 'invalid-type-error))
    (is (typep condition 'type-error))
    (is (typep condition 'invalid-argument-error))
    (is (not (typep condition 'invalid-range-error)))
    (is (not (typep condition 'invalid-option-error))))
  ;; MAKE-CONSTRAINTS (src/geometry.lisp:194-200) signals INVALID-RANGE-ERROR
  ;; for a legally-typed but out-of-range MAX-WIDTH.
  (let ((condition
          (handler-case
              (progn (make-constraints :min-width 10 :max-width 3) nil)
            (error (c) c))))
    (is (typep condition 'invalid-range-error))
    (is (typep condition 'invalid-argument-error))
    (is (not (typep condition 'invalid-type-error)))
    (is (not (typep condition 'invalid-option-error)))))

(deftest condition-hierarchy-distinguishes-option-index-and-capability
    (:conditions)
  ;; RADIO-WIDGET-SELECT (src/input-choice-controls.lisp:87-92) reaches
  ;; %CONTROL-CHECK-INDEX (:24), which signals INDEX-OUT-OF-BOUNDS-ERROR.  A
  ;; handler scoped to the sibling type INVALID-OPTION-ERROR must not catch
  ;; it -- proving positively that the two subtypes are distinguishable, not
  ;; merely that the right handler happens to fire.
  (let ((radio (make-radio-widget '("A" "B" "C")))
        (sibling-caught nil)
        (correct-condition nil))
    (handler-case
        (handler-case (radio-widget-select radio 9)
          (invalid-option-error (c) (setf sibling-caught c)))
      (error (c) (setf correct-condition c)))
    (is (null sibling-caught))
    (is (typep correct-condition 'index-out-of-bounds-error))
    (is (not (typep correct-condition 'invalid-option-error)))
    (is-equal 9 (index-out-of-bounds-error-index correct-condition))
    (is-equal 3 (index-out-of-bounds-error-count correct-condition)))
  ;; BACKEND-SET-CAPABILITY (src/backend.lisp:136-143) reaches
  ;; %CHECK-BACKEND-CAPABILITY (:28), which signals INVALID-OPTION-ERROR.  A
  ;; handler scoped to the sibling type INDEX-OUT-OF-BOUNDS-ERROR must not
  ;; catch it.
  (let ((backend (make-backend :size (make-size 4 3)))
        (sibling-caught nil)
        (correct-condition nil))
    (handler-case
        (handler-case (backend-set-capability backend :bogus t)
          (index-out-of-bounds-error (c) (setf sibling-caught c)))
      (error (c) (setf correct-condition c)))
    (is (null sibling-caught))
    (is (typep correct-condition 'invalid-option-error))
    (is (not (typep correct-condition 'index-out-of-bounds-error)))
    (is-equal '(:color :unicode :mouse :clipboard :alternate-screen)
              (invalid-option-error-allowed correct-condition))))

(deftest condition-hierarchy-distinguishes-focus-and-clipboard-errors
    (:conditions)
  ;; FOCUS-TREE-SET-CURRENT (src/focus.lisp:65-76) signals FOCUS-ERROR when
  ;; the node is not part of the tree.  A handler scoped to the sibling
  ;; PROTOCOL-ERROR subtype SURFACE-ERROR must not catch it.
  (let* ((root (make-focus-node :root :scope-p t
                                :children (list (make-focus-node
                                                  :child :focusable-p t))))
         (tree (make-focus-tree root))
         (outsider (make-focus-node :outsider :focusable-p t))
         (sibling-caught nil)
         (correct-condition nil))
    (handler-case
        (handler-case (focus-tree-set-current tree outsider)
          (surface-error (c) (setf sibling-caught c)))
      (error (c) (setf correct-condition c)))
    (is (null sibling-caught))
    (is (typep correct-condition 'focus-error))
    (is (typep correct-condition 'protocol-error))
    (is (not (typep correct-condition 'surface-error))))
  ;; ANSI-BACKEND's BACKEND-REQUEST-CLIPBOARD (src/ansi.lisp:447-458) signals
  ;; a bare INVALID-ARGUMENT-ERROR for an invalid OSC 52 selection -- it is
  ;; not one of INVALID-ARGUMENT-ERROR's own subtypes, so a handler scoped to
  ;; INVALID-OPTION-ERROR must not catch it either.
  (let ((backend (make-ansi-backend :stream (make-string-output-stream)))
        (sibling-caught nil)
        (correct-condition nil))
    (handler-case
        (handler-case (backend-request-clipboard backend :selection "bad;selection")
          (invalid-option-error (c) (setf sibling-caught c)))
      (error (c) (setf correct-condition c)))
    (is (null sibling-caught))
    (is (typep correct-condition 'invalid-argument-error))
    (is (not (typep correct-condition 'invalid-option-error)))
    (is (not (typep correct-condition 'invalid-type-error)))))

(deftest condition-hierarchy-preserves-backward-compatibility
    (:conditions)
  ;; A plain (HANDLER-CASE ... (ERROR (C) ...)) must still catch every
  ;; condition this hierarchy signals -- the migration from SIMPLE-ERROR must
  ;; not have narrowed what a generic handler catches.
  (is (typep (handler-case (progn (make-point 1.5 0) nil) (error (c) c))
             'error))
  (is (typep (handler-case (progn (make-constraints :min-width 10 :max-width 3)
                              nil)
               (error (c) c))
             'error))
  (is (typep (handler-case
                 (progn (radio-widget-select (make-radio-widget '("A")) 9)
                        nil)
               (error (c) c))
             'error))
  (is (typep (handler-case
                 (progn (backend-set-capability
                         (make-backend :size (make-size 4 3)) :bogus t)
                        nil)
               (error (c) c))
             'error))
  ;; The specific regression risk of this migration: the geometry
  ;; constructors used to signal CL:TYPE-ERROR directly, and callers may
  ;; still be written against that standard protocol rather than against the
  ;; new INVALID-TYPE-ERROR name.
  (is-equal 'integer
            (handler-case (progn (make-point 1.5 0) nil)
              (type-error (c) (type-error-expected-type c))))
  (is-equal 1.5
            (handler-case (progn (make-point 1.5 0) nil)
              (type-error (c) (type-error-datum c)))))

(deftest condition-hierarchy-slot-payloads-carry-real-values
    (:conditions)
  ;; CALLBACK-CONTRACT-ERROR (src/protocol.lisp:190-200): an event-loop timer
  ;; callback that returns neither an EVENT nor a list of EVENTs.
  (let* ((loop (make-event-loop :clock (lambda () 0)))
         (condition nil))
    (event-loop-schedule loop 0 (lambda (loop task)
                                  (declare (ignore loop task))
                                  :not-an-event))
    (handler-case (event-loop-step loop :now 0)
      (error (c) (setf condition c)))
    (is (typep condition 'callback-contract-error))
    (is-equal "event loop timer callback"
              (callback-contract-error-callback condition))
    (is-equal :not-an-event (callback-contract-error-value condition))))

(deftest condition-hierarchy-report-strings-name-parameter-and-value
    (:conditions)
  ;; PRINC-TO-STRING must still name the offending parameter and the
  ;; offending value -- the migration must not have silently dropped
  ;; information that was in the old SIMPLE-ERROR message strings.
  (let ((report (princ-to-string
                 (handler-case (progn (make-point 1.5 0) nil)
                   (error (c) c)))))
    (is (search "X" report))
    (is (search "1.5" report)))
  (let ((report (princ-to-string
                 (handler-case
                     (progn (make-constraints :min-width 10 :max-width 3)
                            nil)
                   (error (c) c)))))
    (is (search "MAX-WIDTH" report))
    (is (search "3" report)))
  (let ((report (princ-to-string
                 (handler-case
                     (progn (backend-set-capability
                             (make-backend :size (make-size 4 3)) :bogus t)
                            nil)
                   (error (c) c)))))
    (is (search "CAPABILITY" report))
    (is (search "BOGUS" report)))
  (let ((report (princ-to-string
                 (handler-case
                     (progn (radio-widget-select
                             (make-radio-widget '("A" "B" "C")) 9)
                            nil)
                   (error (c) c)))))
    (is (search "9" report))
    (is (search "options" report))))

(deftest condition-hierarchy-bounds-large-invalid-parser-input
    (:conditions)
  ;; TERMINAL-INPUT-PARSER-FEED's whole-input site (src/input-parser.lisp:136)
  ;; passes its DATUM through BOUNDED-DATUM.  A signalled condition can
  ;; outlive the call that signalled it (BACKEND-LAST-ERROR,
  ;; TTY-RUNTIME-LAST-ERROR retain one for the object's whole lifetime), so an
  ;; oversized invalid input must not be retained verbatim.
  (let* ((parser (make-terminal-input-parser))
         (huge-invalid-input (make-list 5000 :initial-element 1))
         (condition
           (handler-case
               (progn (terminal-input-parser-feed parser huge-invalid-input)
                      nil)
             (error (c) c))))
    (is (typep condition 'invalid-type-error))
    (let ((datum (invalid-argument-error-datum condition)))
      (is (stringp datum))
      (is (not (eq datum huge-invalid-input)))
      ;; A verbatim PRIN1-TO-STRING of 5000 elements would run well past a
      ;; thousand characters; BOUNDED-DATUM's *PRINT-LENGTH* of 10 and
      ;; *PRINT-LEVEL* of 3 keep it far shorter.
      (is (< (length datum) 200)))))

(deftest condition-hierarchy-bounds-datum-character-length
    (:conditions)
  ;; *PRINT-LENGTH* and *PRINT-LEVEL* bound how many elements PRIN1 descends
  ;; into, not the character length of the string it produces: a short list
  ;; of ten long strings still prints thousands of characters through those
  ;; two alone.  TERMINAL-INPUT-PARSER-FEED's non-string/non-vector branch
  ;; (src/input-parser.lisp) passes such a value through BOUNDED-DATUM, which
  ;; must cap the printed representation by an absolute character count.
  (let* ((parser (make-terminal-input-parser))
         (long-strings (loop for i below 10
                              collect (make-string
                                       500 :initial-element (code-char (+ 65 i)))))
         (condition
           (handler-case
               (progn (terminal-input-parser-feed parser long-strings) nil)
             (error (c) c))))
    (is (typep condition 'invalid-type-error))
    (let ((datum (invalid-argument-error-datum condition)))
      (is (stringp datum))
      ;; A verbatim PRIN1-TO-STRING of these ten 500-character strings runs
      ;; to roughly 5000 characters even with *PRINT-LENGTH* 10; BOUNDED-DATUM's
      ;; absolute character cap (200, plus room for a truncation marker) must
      ;; keep the result far shorter.
      (is (<= (length datum) 250)))))

(deftest condition-hierarchy-strips-control-characters-from-datum
    (:conditions)
  ;; PRIN1 escapes only #\" and #\\ in a string; a raw ESC byte survives into
  ;; the printed representation untouched.  Untrusted terminal input reaches
  ;; conditions via TERMINAL-INPUT-PARSER-FEED (src/input-parser.lisp), and an
  ;; application printing such a condition to a live terminal -- the normal
  ;; thing to do with an error -- would have that ESC re-interpreted as a
  ;; terminal escape sequence.  BOUNDED-DATUM must strip every control byte.
  (let* ((parser (make-terminal-input-parser))
         (poisoned (list (format nil "~Cinjected" (code-char 27))))
         (condition
           (handler-case
               (progn (terminal-input-parser-feed parser poisoned) nil)
             (error (c) c))))
    (is (typep condition 'invalid-type-error))
    (let ((datum (invalid-argument-error-datum condition)))
      (is (stringp datum))
      (is (null (find-if (lambda (char) (< (char-code char) 32)) datum))))))

(deftest condition-hierarchy-invalid-option-report-includes-detail
    (:conditions)
  ;; %NORMALIZE-MODIFIER (src/event.lisp) signals INVALID-OPTION-ERROR with a
  ;; carefully-worded :DETAIL explaining which modifier designators are
  ;; accepted.  INVALID-OPTION-ERROR's report must use that :DETAIL like its
  ;; siblings INVALID-ARGUMENT-ERROR and CALLBACK-CONTRACT-ERROR already do,
  ;; rather than silently discarding it in favor of the generated sentence.
  (let ((report (princ-to-string
                 (handler-case (progn (normalize-modifiers '("bogus")) nil)
                   (error (c) c)))))
    (is (search "Unsupported modifier designator" report))))

(deftest condition-hierarchy-invalid-range-report-includes-detail
    (:conditions)
  ;; MAKE-CONSTRAINTS (src/geometry.lisp:194-200) signals INVALID-RANGE-ERROR
  ;; with a :DETAIL spelling out the MAX-WIDTH/MIN-WIDTH comparison.
  ;; INVALID-RANGE-ERROR's report must use that :DETAIL like its siblings
  ;; INVALID-ARGUMENT-ERROR and INVALID-OPTION-ERROR already do, rather than
  ;; silently discarding it in favor of the generated sentence.
  (let ((report (princ-to-string
                 (handler-case
                     (progn (make-constraints :min-width 10 :max-width 3)
                            nil)
                   (error (c) c)))))
    (is (search "MAX-WIDTH 3 cannot be smaller than MIN-WIDTH 10" report))))

(deftest condition-hierarchy-bounds-backend-capability-states-datum
    (:conditions)
  ;; %COPY-CAPABILITY-STATES (src/backend.lisp) signals INVALID-TYPE-ERROR for
  ;; a non-hash-table :CAPABILITY-STATES argument.  That argument is
  ;; caller-supplied and can be arbitrarily large, so it must pass through
  ;; BOUNDED-DATUM like every other datum that can grow without bound.
  (let* ((huge (loop for i below 10
                      collect (make-string
                               500 :initial-element (code-char (+ 65 i)))))
         (condition
           (handler-case (progn (make-backend :capability-states huge) nil)
             (error (c) c))))
    (is (typep condition 'invalid-type-error))
    (let ((datum (invalid-argument-error-datum condition)))
      (is (stringp datum))
      (is (<= (length datum) 250)))))
