(in-package #:cl-tui-kit/core)

;;;; Every condition this library signals inherits CL-TUI-KIT-ERROR, so an
;;;; application can distinguish a toolkit rejection from an error raised by its
;;;; own code.  Before this hierarchy existed the toolkit signalled SIMPLE-ERROR
;;;; everywhere, which left message-string matching as the only way to tell one
;;;; failure from another.

(defparameter *condition-datum-print-length* 10
  "Sequence length retained when BOUNDED-DATUM truncates an unbounded value.")

(defparameter *condition-datum-print-level* 3
  "Nesting depth retained when BOUNDED-DATUM truncates an unbounded value.")

(defparameter *condition-datum-print-characters* 200
  "Character count retained when BOUNDED-DATUM truncates an unbounded value's
printed representation.")

(defun %escape-control-characters (string)
  (with-output-to-string (out)
    (loop for char across string
          do (if (or (< (char-code char) 32) (= (char-code char) 127))
                 (format out "\\x~2,'0X" (char-code char))
                 (write-char char out)))))

(defun bounded-datum (value)
  "Return VALUE itself when it cannot grow without bound, otherwise a printed
representation of it that is bounded to *CONDITION-DATUM-PRINT-CHARACTERS*
characters and contains no raw control character.

*PRINT-LENGTH* and *PRINT-LEVEL* bound how many elements PRIN1 descends into,
not the character length of the string it produces: a single long string, or
a short list of long strings, still prints without bound under those two
alone, so the printed representation is truncated by character count as a
second, absolute pass.  PRIN1 also escapes only \" and \\ in a string, leaving
raw control bytes such as ESC untouched; a condition signalled from untrusted
terminal input (see src/input-parser.lisp and src/protocol.lisp) can carry one
into a report an application prints to a live terminal, where it would be
re-interpreted as a terminal escape sequence, so every character whose
CHAR-CODE is below 32, plus #\\Rubout, is replaced with a \\xHH escape.

A signalled condition can outlive the call that signalled it: BACKEND-FAIL
stores one in BACKEND-LAST-ERROR for the lifetime of the backend.  Retaining a
caller-supplied sequence or a callback's return value in that slot would pin an
arbitrarily large object graph, so those call sites pass their datum through
here first."
  (if (typep value '(or number symbol character))
      value
      (let* ((*print-length* *condition-datum-print-length*)
             (*print-level* *condition-datum-print-level*)
             (*print-readably* nil)
             (*print-circle* t)
             (escaped (%escape-control-characters (prin1-to-string value))))
        (if (> (length escaped) *condition-datum-print-characters*)
            (concatenate 'string
                         (subseq escaped 0 *condition-datum-print-characters*)
                         "...(truncated)")
            escaped))))

(defun %context-prefix (context)
  (cond ((null context) "")
        ((stringp context) context)
        (t (string context))))

(define-condition cl-tui-kit-error (error)
  ((context
    :initarg :context
    :initform nil
    :reader cl-tui-kit-error-context
    :documentation "A symbol or string naming the parameter, slot, or operation
the failure is about, or NIL when the failure is not tied to one.")
   (detail
    :initarg :detail
    :initform nil
    :reader cl-tui-kit-error-detail
    :documentation "A human-readable sentence describing the failure, or NIL to
let the subclass compose one from its slots."))
  (:documentation "Root of every condition cl-tui-kit signals.")
  (:report
   (lambda (condition stream)
     (write-string (or (cl-tui-kit-error-detail condition)
                       "cl-tui-kit signalled an error.")
                   stream))))

;;;; Invalid arguments -- the caller passed a value the operation cannot use.

(define-condition invalid-argument-error (cl-tui-kit-error)
  ((datum
    :initarg :datum
    :initform nil
    :reader invalid-argument-error-datum
    :documentation "The offending value, or a truncated printed representation
of it when the value could grow without bound.  See BOUNDED-DATUM."))
  (:documentation "A supplied value is not usable by the operation.")
  (:report
   (lambda (condition stream)
     (let ((detail (cl-tui-kit-error-detail condition)))
       (if detail
           (format stream "~A Got ~S." detail
                   (invalid-argument-error-datum condition))
           (format stream "Invalid ~A: ~S."
                   (%context-prefix (cl-tui-kit-error-context condition))
                   (invalid-argument-error-datum condition)))))))

(define-condition invalid-type-error (invalid-argument-error type-error)
  ()
  (:documentation "A supplied value has the wrong type.

Also inherits CL:TYPE-ERROR so that TYPE-ERROR-DATUM and
TYPE-ERROR-EXPECTED-TYPE keep working for handlers written against the standard
condition, which is what the geometry constructors signalled before this
hierarchy existed.")
  (:report
   (lambda (condition stream)
     (let ((detail (cl-tui-kit-error-detail condition)))
       (if detail
           (format stream "~A Got ~S." detail
                   (invalid-argument-error-datum condition))
           (format stream "~@[~A: ~]expected ~S, got ~S."
                   (let ((context (cl-tui-kit-error-context condition)))
                     (and context (%context-prefix context)))
                   (type-error-expected-type condition)
                   (type-error-datum condition)))))))

(define-condition invalid-range-error (invalid-argument-error)
  ((expected
    :initarg :expected
    :initform nil
    :reader invalid-range-error-expected
    :documentation "A human-readable description of the accepted range, such as
\"a positive integer\" or \"a real number between 0 and 1\"."))
  (:documentation "A supplied value has the right type but falls outside the
range the operation accepts.")
  (:report
   (lambda (condition stream)
     (let ((detail (cl-tui-kit-error-detail condition)))
       (if detail
           (format stream "~A Got ~S." detail
                   (invalid-argument-error-datum condition))
           (let ((context (cl-tui-kit-error-context condition)))
             (format stream "~:[Expected~;~:*~A must be~] ~A, got ~S."
                     (and context (%context-prefix context))
                     (or (invalid-range-error-expected condition)
                         "a value inside the accepted range")
                     (invalid-argument-error-datum condition))))))))

(define-condition invalid-option-error (invalid-argument-error)
  ((allowed
    :initarg :allowed
    :initform nil
    :reader invalid-option-error-allowed
    :documentation "The list of values the operation accepts here."))
  (:documentation "A supplied value is not a member of the set the operation
accepts, such as an unknown keyword or an unrecognized option name.")
  (:report
   (lambda (condition stream)
     (let ((detail (cl-tui-kit-error-detail condition)))
       (if detail
           (format stream "~A Got ~S." detail
                   (invalid-argument-error-datum condition))
           (format stream "Invalid ~A: ~S.~@[ Expected one of ~{~S~^, ~}.~]"
                   (%context-prefix (or (cl-tui-kit-error-context condition)
                                        "option"))
                   (invalid-argument-error-datum condition)
                   (invalid-option-error-allowed condition)))))))

(define-condition index-out-of-bounds-error (invalid-argument-error)
  ((index
    :initarg :index
    :initform nil
    :reader index-out-of-bounds-error-index
    :documentation "The index that was requested.")
   (count
    :initarg :count
    :initform nil
    :reader index-out-of-bounds-error-count
    :documentation "The number of elements actually available."))
  (:documentation "An index falls outside the collection it addresses.")
  (:report
   (lambda (condition stream)
     (let ((detail (cl-tui-kit-error-detail condition)))
       (if detail
           (format stream "~A Got ~S." detail
                   (invalid-argument-error-datum condition))
           (format stream "Index ~D is outside the range of ~D ~A."
                   (index-out-of-bounds-error-index condition)
                   (index-out-of-bounds-error-count condition)
                   (%context-prefix (or (cl-tui-kit-error-context condition)
                                        "elements"))))))))

;;;; Protocol violations -- the arguments were individually acceptable but the
;;;; structure or the contract they participate in was broken.

(define-condition protocol-error (cl-tui-kit-error)
  ()
  (:documentation "A structural invariant of a toolkit protocol was broken."))

(define-condition focus-error (protocol-error)
  ()
  (:documentation "A focus operation named a node that does not belong to the
tree, or that lies outside the active modal scope."))

(define-condition surface-error (protocol-error)
  ()
  (:documentation "A cell or surface invariant was broken, such as a
continuation cell carrying content or a drawable cell whose display width does
not match its span."))

(define-condition callback-contract-error (protocol-error)
  ((callback
    :initarg :callback
    :initform nil
    :reader callback-contract-error-callback
    :documentation "A symbol or string naming the callback that misbehaved.")
   (value
    :initarg :value
    :initform nil
    :reader callback-contract-error-value
    :documentation "What the callback returned, truncated by BOUNDED-DATUM when
it could grow without bound."))
  (:documentation "A caller-supplied callback returned a value the protocol
cannot use.")
  (:report
   (lambda (condition stream)
     (format stream "~A Got ~S."
             (or (cl-tui-kit-error-detail condition)
                 (format nil "Callback ~A returned an unusable value."
                         (%context-prefix
                          (callback-contract-error-callback condition))))
             (callback-contract-error-value condition)))))

;;;; Lifecycle violations -- the operation is well-formed but not legal for the
;;;; object's current state.

(define-condition lifecycle-error (cl-tui-kit-error)
  ((current-state
    :initarg :current-state
    :initform nil
    :reader lifecycle-error-current-state
    :documentation "The state the object was in when the operation was
attempted.")
   (requested-operation
    :initarg :requested-operation
    :initform nil
    :reader lifecycle-error-requested-operation
    :documentation "A symbol naming the operation that was refused."))
  (:documentation "An operation was attempted against an object whose current
state does not permit it."))
