(in-package #:cl-tui-kit/core)

;;;; Incremental terminal input

(defstruct (terminal-input-parser
            (:constructor %make-terminal-input-parser
                (%buffer %pending-octets %in-paste-p %paste-buffer
                 max-sequence-length max-paste-length)))
  "State for parsing a terminal input byte stream.

The parser deliberately has no stream, thread, or file-descriptor dependency.
An input source owns those resources and feeds octets or strings into this state
machine. Incomplete escape sequences and UTF-8 sequences remain buffered until
more input arrives."
  (%buffer "" :type string)
  (%pending-octets '() :type list)
  (%in-paste-p nil :type boolean)
  (%paste-buffer "" :type string)
  (max-sequence-length 256 :type (integer 1 *))
  (max-paste-length (* 1024 1024) :type (integer 1 *)))

;;; The slots are mutable state, so their generated accessors remain private.
;;; Public accessors below are ordinary functions and return defensive copies
;;; for string and list values.

(defun make-terminal-input-parser (&key (max-sequence-length 256)
                                        (max-paste-length (* 1024 1024)))
  "Create an incremental parser with bounded control and paste buffers."
  (check-type max-sequence-length (integer 1 *))
  (check-type max-paste-length (integer 1 *))
  (%make-terminal-input-parser "" '() nil ""
                               max-sequence-length max-paste-length))

(defun terminal-input-parser-reset (parser)
  "Discard all buffered input while retaining parser limits."
  (check-type parser terminal-input-parser)
  (setf (terminal-input-parser-%buffer parser) ""
        (terminal-input-parser-%pending-octets parser) '()
        (terminal-input-parser-%in-paste-p parser) nil
        (terminal-input-parser-%paste-buffer parser) "")
  parser)

(defun terminal-input-parser-buffer (parser)
  "Return a copy of PARSER's buffered but not yet drained input.

The returned string is a fresh copy; mutating it does not affect the
parser's internal state. Call TERMINAL-INPUT-PARSER-RESET to clear that
state in a way that keeps the state machine's other buffers consistent."
  (check-type parser terminal-input-parser)
  (copy-seq (terminal-input-parser-%buffer parser)))

(defun terminal-input-parser-pending-octets (parser)
  "Return a copy of PARSER's buffered but not yet decoded UTF-8 octets.

The returned list is a fresh copy; mutating it does not affect the
parser's internal state. Call TERMINAL-INPUT-PARSER-RESET to clear that
state in a way that keeps the state machine's other buffers consistent."
  (check-type parser terminal-input-parser)
  (copy-list (terminal-input-parser-%pending-octets parser)))

(defun terminal-input-parser-in-paste-p (parser)
  "Return true when PARSER is currently inside a bracketed paste.

This is internal parser state and must not be mutated directly; call
TERMINAL-INPUT-PARSER-RESET to clear it in a way that keeps the state
machine's other buffers consistent."
  (check-type parser terminal-input-parser)
  (terminal-input-parser-%in-paste-p parser))

(defun terminal-input-parser-paste-buffer (parser)
  "Return a copy of PARSER's accumulated bracketed-paste text.

The returned string is a fresh copy; mutating it does not affect the
parser's internal state. Call TERMINAL-INPUT-PARSER-RESET to clear that
state in a way that keeps the state machine's other buffers consistent."
  (check-type parser terminal-input-parser)
  (copy-seq (terminal-input-parser-%paste-buffer parser)))

(defun terminal-input-parser-pending-p (parser)
  "Return true when PARSER is waiting for more input."
  (check-type parser terminal-input-parser)
  (not (null
        (or (plusp (length (terminal-input-parser-%buffer parser)))
            (terminal-input-parser-%pending-octets parser)
            (terminal-input-parser-%in-paste-p parser)))))

(defun %terminal-input-parser-utf8-decode-one (octets)
  (let* ((first (first octets))
         (needed (cond ((< first #x80) 1)
                       ((<= #xc2 first #xdf) 2)
                       ((<= #xe0 first #xef) 3)
                       ((<= #xf0 first #xf4) 4)
                       (t nil))))
    (cond
      ((null needed)
       (values (code-char #xfffd) 1 :invalid))
      ((< (length octets) needed)
       (values nil 0 :incomplete))
      ((= needed 1)
       (values (code-char first) 1 :valid))
      (t
       (let ((rest (subseq octets 1 needed)))
         (if (or (not (every (lambda (byte) (<= #x80 byte #xbf)) rest))
                 (and (= needed 3)
                      (or (and (= first #xe0) (< (first rest) #xa0))
                          (and (= first #xed) (> (first rest) #x9f))))
                 (and (= needed 4)
                      (or (and (= first #xf0) (< (first rest) #x90))
                          (and (= first #xf4) (> (first rest) #x8f)))))
             (values (code-char #xfffd) 1 :invalid)
             (let ((code (case needed
                           (2 (+ (ash (logand first #x1f) 6)
                                 (logand (first rest) #x3f)))
                           (3 (+ (ash (logand first #x0f) 12)
                                 (ash (logand (first rest) #x3f) 6)
                                 (logand (second rest) #x3f)))
                           (4 (+ (ash (logand first #x07) 18)
                                 (ash (logand (first rest) #x3f) 12)
                                 (ash (logand (second rest) #x3f) 6)
                                 (logand (third rest) #x3f))))))
               (values (or (code-char code) (code-char #xfffd))
                       needed :valid))))))))

(defun %terminal-input-parser-append-octets (parser octets)
  (let ((remaining (append (terminal-input-parser-%pending-octets parser)
                           (coerce octets 'list))))
    (setf (terminal-input-parser-%pending-octets parser) '())
    (loop while remaining do
      (multiple-value-bind (character consumed status)
          (%terminal-input-parser-utf8-decode-one remaining)
        (case status
          (:incomplete
           (setf (terminal-input-parser-%pending-octets parser) remaining)
           (return))
          (otherwise
           (setf remaining (nthcdr consumed remaining)
                 (terminal-input-parser-%buffer parser)
                 (concatenate 'string
                              (terminal-input-parser-%buffer parser)
                              (string character))))))))
  parser)

(defun %terminal-input-parser-plain-character-p (character)
  (let ((code (char-code character)))
    (and (/= code 27)
         (> code 31)
         (/= code 127))))

(defun %terminal-input-parser-split-parameters (body)
  (let ((length (length body))
        (start 0)
        (parts '()))
    (loop for index from 0 to length do
      (when (or (= index length)
                (char= (char body index) #\;))
        (push (subseq body start index) parts)
        (setf start (1+ index))))
    (nreverse parts)))
