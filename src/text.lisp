(in-package #:cl-tui-kit/core)

;;;; A deliberately small, centralized terminal-cell width policy.
;;;; It groups combining marks and ZWJ sequences well enough for normal TUI
;;;; labels, while documenting that it is not a full UAX #29 implementation.

(defparameter *ambiguous-width* :narrow
  "Width policy for East Asian Ambiguous characters: :NARROW or :WIDE.")

(defmacro with-ambiguous-width ((width) &body body)
  `(let ((*ambiguous-width* ,width))
     ,@body))

(defun %unicode-range-p (code low high)
  (<= low code high))

(defun %unicode-range-member-p (code ranges)
  (some (lambda (range)
          (%unicode-range-p code (first range) (second range)))
        ranges))

(defmacro define-unicode-range-predicate (name ranges)
  `(defun ,name (code)
     (%unicode-range-member-p code ,ranges)))

(define-unicode-range-predicate %combining-code-p *combining-code-ranges*)

(defun %emoji-modifier-p (code)
  (%unicode-range-p code #x1f3fb #x1f3ff))

(define-unicode-range-predicate %wide-code-p *wide-code-ranges*)

(define-unicode-range-predicate %ambiguous-code-p *ambiguous-code-ranges*)

(defun cell-width (character &optional (ambiguous-width *ambiguous-width*))
  "Return the terminal-cell width of one code point.

Combining characters, variation selectors, emoji modifiers, controls, and
zero-width joiners return zero.  Grapheme-like clusters should be passed to
TEXT-UNIT-WIDTH instead."
  (let ((code (char-code character)))
    (cond
      ((or (zerop code) (< code 32) (= code 127)) 0)
      ((or (%combining-code-p code)
           (= code #x200b) (= code #x200c) (= code #x200d)
           (%emoji-modifier-p code)) 0)
      ((%wide-code-p code) 2)
      ((and (eq ambiguous-width :wide) (%ambiguous-code-p code)) 2)
      (t 1))))

(defun text-units (text)
  "Split TEXT into approximate grapheme units.

The grouping covers combining marks, variation selectors, emoji modifiers,
and common ZWJ sequences.  It intentionally does not claim full Unicode
grapheme-cluster conformance; see docs/src/guide/text-layout.md."
  (check-type text string)
  (let ((units '())
        (current '())
        (join-next nil))
    (labels ((append-character (character)
               (push character current))
             (finish ()
               (when current
                 (push (coerce (nreverse current) 'string) units))
               (setf current nil)))
      (loop for character across text
            for code = (char-code character)
            do (cond
                 ((or (%combining-code-p code)
                      (%emoji-modifier-p code)
                      (%unicode-range-p code #xfe00 #xfe0f))
                  (append-character character))
                 ((= code #x200d)
                  (append-character character)
                  (setf join-next t))
                 (join-next
                  (append-character character)
                  (setf join-next nil))
                 (t
                  (finish)
                  (append-character character))))
      (finish)
      (nreverse units))))

(defun text-unit-width (unit &optional (ambiguous-width *ambiguous-width*))
  (let ((width 0))
    (loop for character across unit
          do (incf width (cell-width character ambiguous-width)))
    (min 2 width)))

(defun string-cell-width (text &key (tab-width 8)
                                     (ambiguous-width *ambiguous-width*))
  (unless (and (integerp tab-width) (plusp tab-width))
    (error 'invalid-range-error
           :context 'tab-width
           :datum tab-width
           :expected "a positive integer"))
  (let ((column 0)
        (maximum 0))
    (dolist (unit (text-units text) maximum)
      (cond
        ((string= unit (string #\Newline))
         (setf maximum (max maximum column) column 0))
        ((string= unit (string #\Tab))
         (let ((step (- tab-width (mod column tab-width))))
           (incf column step)))
        (t
         (incf column (text-unit-width unit ambiguous-width))))
      (setf maximum (max maximum column)))))

(defun clip-text (text max-width &key (tab-width 8)
                                      (ambiguous-width *ambiguous-width*))
  "Clip a single display line to MAX-WIDTH cells without splitting a unit."
  (unless (and (integerp max-width) (>= max-width 0))
    (error 'invalid-range-error
           :context 'max-width
           :datum max-width
           :expected "a non-negative integer"))
  (unless (and (integerp tab-width) (plusp tab-width))
    (error 'invalid-range-error
           :context 'tab-width
           :datum tab-width
           :expected "a positive integer"))
  (let ((column 0)
        (output (make-array 0 :element-type 'character :adjustable t
                              :fill-pointer 0)))
    (dolist (unit (text-units text) (coerce output 'string))
      (when (string= unit (string #\Newline))
        (return (coerce output 'string)))
      (let* ((unit-width (if (string= unit (string #\Tab))
                             (- tab-width (mod column tab-width))
                             (text-unit-width unit ambiguous-width)))
             (next (+ column unit-width)))
        (when (> next max-width)
          (return (coerce output 'string)))
        (if (string= unit (string #\Tab))
            (loop repeat unit-width
              do
              (vector-push-extend #\Space output))
            (loop for character across unit
                  do (vector-push-extend character output)))
        (setf column next)))))

(defun truncate-text (text max-width &key (ellipsis "…") (tab-width 8)
                                           (ambiguous-width *ambiguous-width*))
  "Return TEXT clipped to MAX-WIDTH cells, adding ELLIPSIS when needed."
  (unless (and (integerp max-width) (>= max-width 0))
    (error 'invalid-range-error
           :context 'max-width
           :datum max-width
           :expected "a non-negative integer"))
  (if (<= (string-cell-width text :tab-width tab-width
                             :ambiguous-width ambiguous-width)
          max-width)
      text
      (let ((ellipsis-width (string-cell-width ellipsis
                                                :tab-width tab-width
                                                :ambiguous-width ambiguous-width)))
        (cond
          ((zerop max-width) "")
          ((>= ellipsis-width max-width)
           (clip-text ellipsis max-width :tab-width tab-width
                                     :ambiguous-width ambiguous-width))
          (t
           (concatenate 'string
                        (clip-text text (- max-width ellipsis-width)
                                   :tab-width tab-width
                                   :ambiguous-width ambiguous-width)
                        ellipsis))))))
